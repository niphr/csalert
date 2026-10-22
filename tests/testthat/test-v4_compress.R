# ens_compress_v4() stores each base measure as a median and 9 percentiles.
# as_ensemble_v4() reads the table back as a compressed ensemble, and every v4
# step rebuilds the draws it reads.

v4c_probs <- c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975)

# The 9 percentile column names of the measure `m`.
v4c_qcols <- function(m) {
  return(paste0(m, "_", .v4_q_label(v4c_probs)))
}

# Two series of 6 weeks with continuous draws, so that the stored percentiles
# of a row are all different. Week 3 of series "a" is constant at 50, and
# week 4 of series "b" is NA in every draw.
v4c_cont <- function(n_draw = 1000L) {
  set.seed(11)
  d <- data.table::data.table(
    location_code = rep(c("a", "b"), each = 6),
    isoyearweek = rep(sprintf("2023-%02d", 1:6), 2)
  )
  n <- nrow(d)
  mu <- log(100 + 10 * seq_len(n))
  cases <- matrix(stats::rlnorm(n * n_draw, mu, 0.3), n, n_draw)
  other <- matrix(stats::rlnorm(n * n_draw, mu + 1, 0.2), n, n_draw)
  cases[3, ] <- 50
  cases[10, ] <- NA_real_
  return(csfmt_ensemble_v4(
    d,
    id_cols = "location_code",
    draws = list(cases = cases, other = other)
  ))
}

# Two series of 320 weeks with a winter peak in each season, for the steps.
# HLM needs 5 years of baseline, and MEM needs earlier seasons. The tested
# are the positives plus the negatives.
v4c_long <- function(n_draw = 50L) {
  set.seed(12)
  cal <- cstime::dates_by_isoyearweek$isoyearweek
  iyw <- cal[match("2017-30", cal) + 0:319]
  d <- data.table::data.table(
    location_code = rep(c("a", "b"), each = 320),
    isoyearweek = rep(iyw, 2)
  )
  n <- nrow(d)
  sw <- cstime::isoyearweek_to_seasonweek_n(d$isoyearweek)
  lam <- 20 + 60 * exp(-(sw - 25)^2 / 40)
  positive <- matrix(stats::rpois(n * n_draw, lam), n, n_draw)
  tested <- positive + matrix(stats::rpois(n * n_draw, 1000), n, n_draw)
  return(csfmt_ensemble_v4(
    d,
    id_cols = "location_code",
    draws = list(positive = positive * 1, tested = tested * 1)
  ))
}

# The Spearman correlation of every pair of rows in `rows` of `M`.
v4c_pair_cor <- function(M, rows) {
  pairs <- utils::combn(rows, 2)
  return(apply(pairs, 2, function(ij) {
    return(stats::cor(M[ij[1], ], M[ij[2], ], method = "spearman"))
  }))
}

test_that("the round trip works with every attribute stripped", {
  full <- short_term_trend_v4(v4c_cont(), "cases", width = 3, seed = 4)
  tab <- ens_compress_v4(full)

  # The table keeps $data, and adds a median and 9 percentiles per base
  # measure. The derived draw matrices of the trend are not stored.
  base <- c("cases", "other")
  want <- c(
    names(full$data),
    unlist(lapply(base, function(m) {
      return(c(m, v4c_qcols(m)))
    }))
  )
  expect_identical(names(tab), want)
  expect_false(any(grepl("_trend_(beta1|se)$", names(tab))))
  expect_identical(tab$cases_trend_pinc, full$data$cases_trend_pinc)
  expect_equal(
    tab$other,
    matrixStats::rowMedians(full$draws$other),
    tolerance = 1e-12
  )
  expect_equal(
    unname(as.matrix(tab[, v4c_qcols("other"), with = FALSE])),
    unname(matrixStats::rowQuantiles(full$draws$other, probs = v4c_probs)),
    tolerance = 1e-12
  )
  # A constant row keeps its value and gets NA percentiles. An all-NA row is
  # NA.
  expect_identical(tab$cases[3], 50)
  expect_true(all(is.na(unlist(tab[3, v4c_qcols("cases"), with = FALSE]))))
  expect_true(is.na(tab$cases[10]))

  plain <- data.table::as.data.table(as.list(tab))
  expect_null(attr(plain, "sorted"))
  y <- as_ensemble_v4(plain, id_cols = "location_code")
  expect_s3_class(y, "csfmt_ensemble_v4")
  expect_identical(y$state, "compressed")
  expect_identical(y$n_sim, 1000L)
  expect_identical(length(y$draws), 0L)
  expect_identical(.v4_measures(y), base)
  expect_equal(ens_compress_v4(y), tab)

  R <- .v4_draws(y, "cases")
  expect_identical(dim(R), c(12L, 1000L))
  expect_true(all(R[3, ] == 50))
  expect_true(all(is.na(R[10, ])))
})

test_that("a table column is a stored measure only with its 9 percentiles", {
  tab <- ens_compress_v4(v4c_cont())
  tab[, cases_q50x0 := NULL]
  y <- as_ensemble_v4(tab, id_cols = "location_code")
  expect_identical(.v4_measures(y), "other")
  expect_error(.v4_draws(y, "cases"), "must name one matrix in \\$draws")

  # A name with a reserved suffix is a derived summary, not a measure.
  tab <- ens_compress_v4(v4c_cont())
  tab[, (c("other_hlm", v4c_qcols("other_hlm"))) := 1]
  y <- as_ensemble_v4(tab, id_cols = "location_code")
  expect_identical(.v4_measures(y), c("cases", "other"))
})

test_that("two rebuilds of the same table are identical", {
  tab <- ens_compress_v4(v4c_cont())
  y1 <- as_ensemble_v4(tab, "location_code", n_sim = 500L)
  y2 <- as_ensemble_v4(tab, "location_code", n_sim = 500L)
  # The measures are read in the opposite order, so the u cannot depend on
  # which measure comes first.
  c1 <- .v4_draws(y1, "cases")
  o1 <- .v4_draws(y1, "other")
  o2 <- .v4_draws(y2, "other")
  c2 <- .v4_draws(y2, "cases")
  expect_identical(c1, c2)
  expect_identical(o1, o2)
})

test_that("the rebuild has one rule, and no function takes a rule argument", {
  expect_false("rule" %in% names(formals(.v4_as_ensemble)))
  expect_false("rule" %in% names(formals(.v4_draw_u)))
  expect_false("rule" %in% names(formals(as_ensemble_v4)))
})

# The pattern of rebuild-rule state: the old constant, the `$rule` slot, and
# a `rule =` argument.
v4c_rule_state <- "V4_REBUILD_RULES|\\$rule\\b|\\brule\\s*="

test_that("a compressed ensemble has no rule slot, and no v4 function reads one", {
  y <- as_ensemble_v4(ens_compress_v4(v4c_cont()), "location_code")
  expect_false("rule" %in% names(y))
  ns <- asNamespace("csalert")
  expect_false(exists(".V4_REBUILD_RULES", envir = ns, inherits = FALSE))
  v4 <- grep("^\\.v4_|_v4$", ls(ns, all.names = TRUE), value = TRUE)
  fns <- v4[vapply(v4, function(f) is.function(ns[[f]]), logical(1))]
  expect_gt(length(fns), 50)
  reads <- vapply(
    fns,
    function(f) {
      return(any(grepl(v4c_rule_state, deparse(ns[[f]]))))
    },
    logical(1)
  )
  expect_identical(fns[reads], character(0))
})

test_that("no R/v4_*.R file defines or reads rebuild-rule state", {
  r_dir <- testthat::test_path("..", "..", "R")
  skip_if_not(dir.exists(r_dir), "R/ is not in a built package")
  files <- list.files(r_dir, pattern = "^v4_.*\\.R$", full.names = TRUE)
  expect_gt(length(files), 5)
  hits <- unlist(lapply(files, function(f) {
    L <- readLines(f, warn = FALSE)
    return(sprintf("%s:%d", basename(f), grep(v4c_rule_state, L)))
  }))
  expect_identical(as.character(hits), character(0))
})

test_that("as_ensemble_v4 takes a data.frame, and does not change it", {
  tab <- ens_compress_v4(v4c_cont())
  df <- as.data.frame(tab)
  before <- data.table::copy(df)
  from_dt <- as_ensemble_v4(tab, "location_code", n_sim = 300L)
  from_df <- tryCatch(
    as_ensemble_v4(df, "location_code", n_sim = 300L),
    error = function(e) e
  )
  expect_s3_class(from_df, "csfmt_ensemble_v4")
  expect_identical(df, before)
  expect_identical(class(df), "data.frame")
  skip_if_not(inherits(from_df, "csfmt_ensemble_v4"))
  expect_identical(from_df$data, from_dt$data)
  expect_identical(.v4_draws(from_df, "cases"), .v4_draws(from_dt, "cases"))
  expect_identical(.v4_draws(from_df, "other"), .v4_draws(from_dt, "other"))
})

test_that("compress, as_ensemble_v4 and every step leave .Random.seed unchanged", {
  full <- v4c_long()
  run <- function() {
    y <- as_ensemble_v4(
      ens_compress_v4(full),
      id_cols = "location_code",
      n_sim = 100L
    )
    y <- suppressWarnings(ens_add_rate_v4(
      y,
      "positive",
      "tested",
      name = "pos_pr100"
    ))
    y <- short_term_trend_v4(
      y,
      "positive",
      width = 5,
      denominator = "tested",
      seed = 4
    )
    y <- signal_detection_hlm_v4(y, "pos_pr100")
    y <- suppressMessages(mem_thresholds_v4(y, "pos_pr100"))
    return(y)
  }
  set.seed(31)
  before <- get(".Random.seed", envir = globalenv())
  run()
  # identical() inside expect_true(): testthat cannot print a diff of two
  # .Random.seed vectors.
  expect_true(identical(get(".Random.seed", envir = globalenv()), before))

  env <- globalenv()
  saved <- get(".Random.seed", envir = env)
  rm(".Random.seed", envir = env)
  run()
  absent <- !exists(".Random.seed", envir = env, inherits = FALSE)
  assign(".Random.seed", saved, envir = env)
  expect_true(absent)
})

test_that("two weeks of a series have absolute Spearman correlation below 0.1 at n_sim = 20,000", {
  tab <- ens_compress_v4(v4c_cont())
  y <- as_ensemble_v4(tab, "location_code", n_sim = 20000L)
  R <- .v4_draws(y, "other")
  rho <- c(v4c_pair_cor(R, 1:6), v4c_pair_cor(R, 7:12))
  expect_length(rho, 30)
  expect_true(all(abs(rho) < 0.1))
})

test_that("the measures of one week have independent u", {
  # Each measure has its own u, as the numerator and the denominator of
  # nowcast_ecdf_v4() are independent. At n_sim = 2,000 the standard error
  # of a Spearman correlation of 0 is about 0.022.
  tab <- ens_compress_v4(v4c_cont())
  y <- as_ensemble_v4(tab, "location_code", n_sim = 2000L)
  C <- .v4_draws(y, "cases")
  O <- .v4_draws(y, "other")
  # Week 3 of "a" is constant and week 4 of "b" is NA.
  rho <- vapply(
    c(1, 2, 4, 5, 6, 7, 8, 9, 11, 12),
    function(i) {
      return(stats::cor(C[i, ], O[i, ], method = "spearman"))
    },
    numeric(1)
  )
  expect_length(rho, 10)
  expect_true(all(abs(rho) < 0.1))
})

test_that("the rebuilt tails are flat at the stored 2.5% and 97.5%, and the quartiles hold at n_sim = 20,000", {
  tab <- ens_compress_v4(v4c_cont())
  y <- as_ensemble_v4(tab, id_cols = "location_code", n_sim = 20000L)
  R <- .v4_draws(y, "other")
  stored <- as.matrix(tab[, v4c_qcols("other"), with = FALSE])
  rebuilt <- matrixStats::rowQuantiles(R, probs = c(0.025, 0.25, 0.75, 0.975))
  rel <- abs(rebuilt - stored[, c(1, 4, 6, 9)]) / abs(stored[, c(1, 4, 6, 9)])
  expect_true(all(rel < 0.02))
  # Flat tails: no draw lies below the stored 2.5% or above the stored 97.5%.
  expect_identical(matrixStats::rowMins(R), unname(stored[, 1]))
  expect_identical(matrixStats::rowMaxs(R), unname(stored[, 9]))
})

test_that("a rate on a compressed ensemble is the ratio of its rebuilt parts", {
  set.seed(13)
  n <- 4L
  z <- matrix(stats::rgamma(n * 1000, shape = 5, rate = 0.1), n, 1000)
  full <- csfmt_ensemble_v4(
    data.table::data.table(
      location_code = "a",
      isoyearweek = sprintf("2023-%02d", seq_len(n))
    ),
    id_cols = "location_code",
    draws = list(positive = 10 + z, tested = 1000 + 10 * z)
  )
  y <- as_ensemble_v4(
    ens_compress_v4(full),
    id_cols = "location_code",
    n_sim = 2000L
  )
  y <- ens_add_rate_v4(y, "positive", "tested", name = "pos_pr100")
  rate <- y$draws$pos_pr100
  P <- .v4_draws(y, "positive")
  Te <- .v4_draws(y, "tested")
  expect_equal(rate, 100 * P / Te, tolerance = 1e-12)
  # The median and the percentiles of the rate are in $data.
  expect_equal(y$data$pos_pr100, matrixStats::rowMedians(rate))
  expect_true(all(v4c_qcols("pos_pr100") %in% names(y$data)))

  # The stored rate is a measure of the next rebuild. Adding it again from
  # its parts replaces its columns.
  z2 <- as_ensemble_v4(ens_compress_v4(y), id_cols = "location_code")
  expect_true("pos_pr100" %in% .v4_measures(z2))
  z3 <- ens_add_rate_v4(z2, "positive", "tested", name = "pos_pr100")
  expect_identical(names(z3$data), names(z2$data))
  expect_identical(names(z3$draws), "pos_pr100")
})

test_that("the trend runs on a compressed ensemble, and a rerun replaces its columns", {
  y <- as_ensemble_v4(
    ens_compress_v4(v4c_long()),
    id_cols = "location_code",
    n_sim = 100L
  )
  trend <- function(e, width) {
    return(short_term_trend_v4(
      e,
      "positive",
      width = width,
      denominator = "tested",
      seed = 4
    ))
  }
  y1 <- trend(y, 5)
  expect_identical(y1$state, "compressed")
  expect_true(all(
    c("positive_trend_pinc", "positive_trend_gr") %in% names(y1$data)
  ))
  expect_gt(sum(!is.na(y1$data$positive_trend_pinc)), 600)
  expect_identical(dim(y1$draws$positive_trend_beta1), c(640L, 100L))

  y2 <- trend(y1, 7)
  expect_identical(names(y2$data), names(y1$data))
  expect_identical(y2$data, trend(y, 7)$data)

  # A rerun on a stored table that already holds the columns.
  z <- as_ensemble_v4(ens_compress_v4(y1), id_cols = "location_code")
  z2 <- trend(z, 7)
  expect_identical(names(z2$data), names(z$data))
  expect_identical(anyDuplicated(names(z2$data)), 0L)
})

test_that("HLM runs on a compressed ensemble, and a rerun replaces its columns", {
  y <- as_ensemble_v4(
    ens_compress_v4(v4c_long()),
    id_cols = "location_code",
    n_sim = 100L
  )
  y1 <- signal_detection_hlm_v4(y, "positive")
  expect_identical(y1$state, "compressed")
  expect_gt(sum(!is.na(y1$data$positive_hlm_thr)), 100)
  expect_true("positive_hlm_prob_high" %in% names(y1$data))

  y2 <- signal_detection_hlm_v4(y1, "positive", baseline_isoyears = 3)
  expect_identical(names(y2$data), names(y1$data))
  expect_identical(
    y2$data,
    signal_detection_hlm_v4(y, "positive", baseline_isoyears = 3)$data
  )

  z <- as_ensemble_v4(ens_compress_v4(y1), id_cols = "location_code")
  z2 <- signal_detection_hlm_v4(z, "positive", baseline_isoyears = 3)
  expect_identical(names(z2$data), names(z$data))
  expect_identical(anyDuplicated(names(z2$data)), 0L)
})

test_that("MEM runs on a compressed ensemble, and a rerun replaces its columns", {
  y <- as_ensemble_v4(
    ens_compress_v4(v4c_long()),
    id_cols = "location_code",
    n_sim = 100L
  )
  mem <- function(e, min_seasons) {
    return(suppressMessages(mem_thresholds_v4(
      e,
      "positive",
      min_seasons = min_seasons
    )))
  }
  y1 <- mem(y, 2)
  expect_identical(y1$state, "compressed")
  expect_gt(sum(!is.na(y1$data$positive_mem_thr_high)), 100)

  y2 <- mem(y1, 3)
  expect_identical(names(y2$data), names(y1$data))
  expect_identical(y2$data, mem(y, 3)$data)

  z <- as_ensemble_v4(ens_compress_v4(y1), id_cols = "location_code")
  z2 <- mem(z, 3)
  expect_identical(names(z2$data), names(z$data))
  expect_identical(anyDuplicated(names(z2$data)), 0L)
})

test_that("a stored column name of 64 bytes is an error", {
  m <- strrep("m", 58)
  full <- csfmt_ensemble_v4(
    data.table::data.table(location_code = "a", isoyearweek = "2023-01"),
    id_cols = "location_code",
    draws = stats::setNames(list(matrix(c(1, 2, 3), 1)), m)
  )
  # The measure name has 58 bytes, so its percentile names have 64.
  expect_identical(nchar(v4c_qcols(m)[1], type = "bytes"), 64L)
  expect_error(ens_compress_v4(full), "longer than 63 bytes")
})

test_that("a list, matrix or factor column of $data is an error", {
  full <- v4c_cont()
  e <- full
  e$data <- data.table::copy(full$data)[, extra := as.list(seq_len(.N))]
  expect_error(ens_compress_v4(e), "list, matrix or factor columns.*extra")
  e$data <- data.table::copy(full$data)[, extra := factor("x")]
  expect_error(ens_compress_v4(e), "list, matrix or factor columns.*extra")
})

test_that("as_ensemble_v4 checks its arguments", {
  tab <- ens_compress_v4(v4c_cont())
  expect_error(
    as_ensemble_v4(as.list(tab), "location_code"),
    "must be a data.frame or a data.table"
  )
  expect_error(
    as_ensemble_v4(as.matrix(tab), "location_code"),
    "must be a data.frame or a data.table"
  )
  expect_error(
    as_ensemble_v4(tab, "location_code", n_sim = 0),
    "n_sim"
  )
  bad <- data.table::copy(tab)[, other_q05x0 := NULL][, other_q05x0 := "x"]
  expect_error(as_ensemble_v4(bad, "location_code"), "must be numeric")
  y <- as_ensemble_v4(tab, "location_code")
  y$n_sim <- NULL
  expect_error(.v4_validate_ensemble(y), "compressed")
})

test_that("ens_compress_v4 and as_ensemble_v4 are exported", {
  ns_file <- file.path(system.file(package = "csalert"), "NAMESPACE")
  expect_true(file.exists(ns_file))
  ns <- trimws(readLines(ns_file))
  expect_true("export(ens_compress_v4)" %in% ns)
  expect_true("export(as_ensemble_v4)" %in% ns)
})
