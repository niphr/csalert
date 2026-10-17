# mem_thresholds_v4 is a copy of mem_thresholds_v1.csfmt_ensemble_v3. On the
# same draws, its values and its messages MUST be identical() to those of v3.
# Only the names differ.

# The ISO weeks of a series: `n` weeks that end in `last`.
v4m_weeks <- function(n = 370L, last = "2023-03") {
  cal <- cstime::dates_by_isoyearweek
  i <- match(last, cal$isoyearweek)
  return(cal$isoyearweek[seq(i - n + 1L, i)])
}

# The weekly mean of the test series: a winter peak in each season.
v4m_lambda <- function(weeks, peak) {
  sw <- cstime::isoyearweek_to_seasonweek_n(weeks)
  return(20 + peak * exp(-(sw - 25)^2 / 40))
}

# Raw reports of two series over about 7 seasons. With `delays = TRUE`, each
# week is reported over delay days 0 to 34, and the as-of date is 2 days
# after the Monday of the last week. Without, each week is reported once, 3
# days after its Monday, and every week is complete.
v4m_raw <- function(delays, seed = 7L) {
  set.seed(seed)
  cal <- cstime::dates_by_isoyearweek
  weeks <- v4m_weeks()
  monday <- as.Date(cal$mon[match(weeks, cal$isoyearweek)])
  shares <- stats::dgamma(seq(0, 34) + 0.5, shape = 2, rate = 0.3)
  rows <- list()
  for (loc in c("nation", "county03")) {
    n <- stats::rpois(
      length(weeks),
      v4m_lambda(weeks, c(nation = 300, county03 = 90)[[loc]])
    )
    for (k in seq_along(weeks)) {
      if (delays) {
        cnt <- as.integer(stats::rmultinom(1, n[k], shares))
        day <- seq(0, 34)
      } else {
        cnt <- n[k]
        day <- 3
      }
      keep <- cnt > 0L
      rows[[length(rows) + 1L]] <- data.table::data.table(
        isoyearweek_reference = weeks[k],
        reporting_date = monday[k] + day[keep],
        numerator = cnt[keep],
        location_code = loc,
        age = "total"
      )
    }
  }
  raw <- data.table::rbindlist(rows)
  return(raw[raw$reporting_date <= monday[length(monday)] + 2L])
}

# The v3 and the v4 ensemble of the same draws. "ecdf" gives 100 draws from
# the ECDF nowcast, and "pass" one draw from the passthrough. Both get NA
# weeks: three whole weeks of "nation" in its second season, and, with many
# draws, one NA draw in a later week.
v4m_pair <- function(kind) {
  id <- c("location_code", "age")
  raw <- v4m_raw(delays = kind == "ecdf")
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = id)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = id)
  if (kind == "ecdf") {
    set.seed(4)
    e3 <- nowcast_delay_ecdf_v1(tri3, max_delay_days = 35, n_sim = 100)
    e4 <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 100)
  } else {
    e3 <- nowcast_passthrough_to_ensemble_v1(tri3, max_delay_days = 7)
    e4 <- nowcast_passthrough_v4(tri4, max_delay_days = 7)
  }
  na_rows <- which(e4$data$location_code == "nation")[100:102]
  e3$draws$numerator_nowcasted[na_rows, ] <- NA_real_
  e4$draws$numerator[na_rows, ] <- NA_real_
  if (kind == "ecdf") {
    e3$draws$numerator_nowcasted[300, 1] <- NA_real_
    e4$draws$numerator[300, 1] <- NA_real_
  }
  return(list(e3 = e3, e4 = e4, na_rows = na_rows))
}

V4M_Q <- c(
  "q02x5",
  "q05x0",
  "q10x0",
  "q25x0",
  "q50x0",
  "q75x0",
  "q90x0",
  "q95x0",
  "q97x5"
)

V4M_LEVELS <- c("preepidemic", "low", "medium", "high", "veryhigh")

# Each v3 output and its v4 name. "draws" is a draw matrix. "data" is a
# column of $data in v4, and of the ens_collapse() output in v3.
v4m_map <- function(m3, m4) {
  return(data.frame(
    where = c("draws", rep("data", 10)),
    v3 = c(
      paste0(m3, "_status"),
      paste0("mem_", c("preepidemic", "medium", "high", "veryhigh")),
      "mem_n_seasons",
      paste0(m3, "_status_prob_", V4M_LEVELS)
    ),
    v4 = c(
      paste0(m4, "_mem"),
      paste0(m4, "_mem_thr_", c("preepidemic", "medium", "high", "veryhigh")),
      paste0(m4, "_mem_n_seasons"),
      paste0(m4, "_mem_prob_", V4M_LEVELS)
    )
  ))
}

# The v3 outputs that v4 deliberately does not carry. The ordinal percentiles
# of the level codes follow from the per-level shares.
v4m_not_carried <- function(m3) {
  return(list(ordinal_percentiles = paste0(m3, "_status_", V4M_Q)))
}

# The messages of `expr`, with the function name of v3 written as that of v4,
# and the column name in the provisional message cut.
v4m_messages <- function(expr) {
  msg <- testthat::capture_messages(expr)
  msg <- sub("^mem_thresholds_v1", "mem_thresholds_v4", msg)
  return(sub("; see .*$", "", msg))
}

# Run v3 and v4 on the pair, and expect every v3 output to have a v4 name in
# the map with identical values, no output outside the map, and the same
# messages.
v4m_expect_equivalent <- function(pair, ...) {
  e3 <- pair$e3
  e4 <- pair$e4
  expect_identical(e4$data, e3$data)
  expect_identical(e4$draws$numerator, e3$draws$numerator_nowcasted)
  in3_data <- names(ens_collapse(e3))
  in3_draws <- names(e3$draws)
  e4_before <- data.table::copy(e4$data)

  msg3 <- v4m_messages(
    h3 <- mem_thresholds_v1(e3, measure = "numerator_nowcasted", ...)
  )
  msg4 <- v4m_messages(h4 <- mem_thresholds_v4(e4, measure = "numerator", ...))
  # The provisional message is the only output of prefer_seasons.
  expect_identical(msg4, msg3)
  c3 <- ens_collapse(h3)
  map <- v4m_map("numerator_nowcasted", "numerator")
  not_carried <- unlist(v4m_not_carried("numerator_nowcasted"))

  # Each v3 output is in the map or deliberately not carried, and v4 adds
  # nothing outside the map.
  expect_setequal(
    c(setdiff(names(c3), in3_data), setdiff(names(h3$draws), in3_draws)),
    c(map$v3, not_carried)
  )
  expect_identical(
    setdiff(names(h4$data), names(e4$data)),
    map$v4[map$where == "data"]
  )
  expect_identical(
    setdiff(names(h4$draws), names(e4$draws)),
    map$v4[map$where == "draws"]
  )

  for (i in seq_len(nrow(map))) {
    if (map$where[i] == "draws") {
      expect_identical(
        h4$draws[[map$v4[i]]],
        h3$draws[[map$v3[i]]],
        label = map$v4[i]
      )
    } else {
      expect_identical(h4$data[[map$v4[i]]], c3[[map$v3[i]]], label = map$v4[i])
    }
  }
  expect_identical(h4$data[, names(e4$data), with = FALSE], e4_before)
  expect_identical(e4$data, e4_before)
  return(list(h4 = h4, msg = msg4))
}

test_that("with 100 ECDF draws, mem_thresholds_v4 is identical to v3", {
  pair <- v4m_pair("ecdf")
  r <- v4m_expect_equivalent(pair)
  h4 <- r$h4
  n_seasons <- h4$data$numerator_mem_n_seasons
  # The test is not trivial: the first seasons have no fit, some fits are
  # provisional, one season is fit on exactly 4 seasons, the NA weeks have no
  # draws, and some weeks have draws at more than one level.
  expect_gt(sum(is.na(n_seasons)), 100L)
  expect_true(all(c(2L, 4L, 5L) %in% n_seasons))
  expect_match(r$msg, "season\\(s\\) fit on < 5 training seasons", all = FALSE)
  expect_true(all(is.na(h4$draws$numerator_mem[pair$na_rows, ])))
  p <- h4$data$numerator_mem_prob_high
  expect_gt(sum(p > 0 & p < 1, na.rm = TRUE), 0L)
  expect_true(all(1:5 %in% h4$draws$numerator_mem))
})

test_that("with one passthrough draw, mem_thresholds_v4 is identical to v3", {
  pair <- v4m_pair("pass")
  h4 <- v4m_expect_equivalent(pair)$h4
  expect_identical(ncol(h4$draws$numerator_mem), 1L)
  # Some fits are provisional and some are not, and the draws reach 4 levels.
  n_seasons <- h4$data$numerator_mem_n_seasons
  expect_true(any(n_seasons < 5L, na.rm = TRUE))
  expect_true(any(n_seasons >= 5L, na.rm = TRUE))
  expect_true(all(1:4 %in% h4$draws$numerator_mem))
  expect_true(all(is.na(h4$draws$numerator_mem[pair$na_rows, ])))
})

test_that("mem_thresholds_v4 is identical to v3 with other arguments", {
  r <- v4m_expect_equivalent(
    v4m_pair("pass"),
    min_seasons = 3,
    prefer_seasons = 4,
    i.seasons = 3,
    min_weeks_per_season = 40,
    exclude_seasons = c("2018/2019", "1990/1991")
  )
  expect_match(r$msg, "excluding 1 season\\(s\\)", all = FALSE)
  expect_false(any(r$h4$data$numerator_mem_n_seasons > 3, na.rm = TRUE))
})
# A small ensemble of one series over 6 years, with 20 draws.
v4m_small <- function(measure = "cases") {
  weeks <- v4m_weeks(n = 320L)
  set.seed(5)
  draws <- list(matrix(
    stats::rpois(320 * 20, v4m_lambda(weeks, 100)),
    nrow = 320
  ))
  names(draws) <- measure
  return(csfmt_ensemble_v4(
    data.table::data.table(location_code = "nation", isoyearweek = weeks),
    id_cols = "location_code",
    draws = draws
  ))
}

test_that("a rerun on the same measure replaces the columns and the draws", {
  ens <- v4m_small()
  first <- suppressMessages(mem_thresholds_v4(ens, "cases"))
  rerun <- suppressMessages(mem_thresholds_v4(first, "cases", min_seasons = 4))
  fresh <- suppressMessages(mem_thresholds_v4(ens, "cases", min_seasons = 4))
  # min_seasons = 4 leaves the seasons with 2 and 3 training seasons without a
  # fit, so a column left from the first run is visible.
  expect_false(identical(
    first$data$cases_mem_thr_high,
    fresh$data$cases_mem_thr_high
  ))
  expect_identical(anyDuplicated(names(rerun$data)), 0L)
  expect_identical(anyDuplicated(names(rerun$draws)), 0L)
  expect_identical(names(rerun$data), names(fresh$data))
  expect_identical(names(rerun$draws), names(fresh$draws))
  for (col in setdiff(names(fresh$data), names(ens$data))) {
    expect_identical(rerun$data[[col]], fresh$data[[col]], label = col)
  }
  expect_identical(rerun$draws, fresh$draws)
})

test_that("the 63-byte check of the new names runs before the fit", {
  # The fit stops, so only the name check can give the 63-byte error.
  testthat::local_mocked_bindings(
    .v4_mem_estimate_thresholds = function(...) {
      stop("the fit ran", call. = FALSE)
    },
    .package = "csalert"
  )
  # 43 bytes + "_mem_prob_preepidemic" is 64 bytes.
  m <- strrep("n", 43)
  expect_error(mem_thresholds_v4(v4m_small(m), m), "longer than 63 bytes")
  m <- strrep("n", 42)
  expect_error(mem_thresholds_v4(v4m_small(m), m), "the fit ran")
})

test_that("a measure that ends in a reserved suffix is an error", {
  for (m in c("cases_mem", "cases_hlm", "cases_trend_gr")) {
    expect_error(
      mem_thresholds_v4(v4m_small(m), m),
      "reserved suffix",
      label = m
    )
  }
  expect_error(
    mem_thresholds_v4(v4m_small(), "other"),
    "must name one matrix in \\$draws"
  )
})

test_that("mem_thresholds_v4 does not change .Random.seed", {
  ens <- v4m_small()
  set.seed(21)
  before <- get(".Random.seed", envir = globalenv())
  suppressMessages(mem_thresholds_v4(ens, "cases"))
  # identical() inside expect_true(): testthat cannot print a diff of two
  # .Random.seed vectors.
  expect_true(identical(get(".Random.seed", envir = globalenv()), before))

  env <- globalenv()
  saved <- get(".Random.seed", envir = env)
  rm(".Random.seed", envir = env)
  suppressMessages(mem_thresholds_v4(ens, "cases"))
  absent <- !exists(".Random.seed", envir = env, inherits = FALSE)
  assign(".Random.seed", saved, envir = env)
  expect_true(absent)
})

test_that("mem_thresholds_v4 is exported", {
  ns_file <- file.path(system.file(package = "csalert"), "NAMESPACE")
  expect_true(file.exists(ns_file))
  expect_true("export(mem_thresholds_v4)" %in% trimws(readLines(ns_file)))
})

test_that("an unknown named argument is an error", {
  # The function takes no `...`, so a misspelt argument cannot become a
  # silent default. The name is not the start of any argument name: R
  # matches a start such as `prefer_season` to the argument by partial matching.
  expect_error(
    mem_thresholds_v4(v4m_small(), "cases", preferred_seasons = 3),
    "unused argument"
  )
})
