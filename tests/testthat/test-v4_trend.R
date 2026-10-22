# short_term_trend_v4 against 4 oracles: stats::glm() window by window, the
# pinned pre-kernel v1 reference in fixtures/v1_reference.rds, the closed form
# of the growth rate with one draw, and a brute-force simulation with many
# draws.

# A value matches when |v4 - oracle| <= V4T_ABS_TOL or
# |v4 - oracle| <= V4T_REL_TOL * |oracle|.
V4T_ABS_TOL <- 1e-10
V4T_REL_TOL <- 1e-8

# Expect `got` and `want` to have NA in the same places, and to match within
# the tolerance above everywhere else.
v4t_expect_close <- function(got, want, label) {
  expect_identical(is.na(got), is.na(want), label = paste(label, "NA places"))
  gap <- abs(got - want)
  bad <- which(!is.na(gap) & gap > V4T_ABS_TOL & gap > V4T_REL_TOL * abs(want))
  expect(
    length(bad) == 0,
    sprintf(
      "%s differs in %d values, at %s: %s vs %s",
      label,
      length(bad),
      paste(utils::head(bad), collapse = ", "),
      paste(utils::head(got[bad]), collapse = ", "),
      paste(utils::head(want[bad]), collapse = ", ")
    )
  )
}

# A one-draw ensemble from nowcast_passthrough_v4(). `d` holds
# `location_code`, `isoyearweek`, `numerator` and `denominator`, one row per
# series and week. Each week is reported once, 3 days after its Monday. An NA
# count or denominator becomes an NA draw, because the triangle stores it as
# 0.
v4t_pass_dt <- function(d) {
  cal <- cstime::dates_by_isoyearweek
  monday <- as.Date(cal$mon[match(d$isoyearweek, cal$isoyearweek)])
  raw <- data.table::data.table(
    isoyearweek_reference = d$isoyearweek,
    reporting_date = monday + 3,
    numerator = as.numeric(d$numerator),
    denominator = as.numeric(d$denominator),
    location_code = d$location_code
  )
  tri <- csfmt_reporting_triangle_v4(raw, id_cols = "location_code")
  ens <- nowcast_passthrough_v4(
    tri,
    max_delay_days = 7,
    denominator_col = "denominator"
  )
  key_ens <- paste(ens$data$location_code, ens$data$isoyearweek)
  key_raw <- paste(raw$location_code, raw$isoyearweek_reference)
  for (m in c("numerator", "denominator")) {
    na_rows <- key_ens %in% key_raw[is.na(raw[[m]])]
    ens$draws[[m]][na_rows, 1] <- NA_real_
  }
  ens
}

# The same, from one vector of counts and one of denominators per location.
v4t_pass <- function(num, den, first_week = "2023-01") {
  cal <- cstime::dates_by_isoyearweek
  i0 <- match(first_week, cal$isoyearweek)
  d <- data.table::rbindlist(lapply(names(num), function(loc) {
    n <- length(num[[loc]])
    data.table::data.table(
      location_code = loc,
      isoyearweek = cal$isoyearweek[i0 + seq_len(n) - 1L],
      numerator = num[[loc]],
      denominator = den[[loc]]
    )
  }))
  v4t_pass_dt(d)
}

# The test series. Location "a" has 26 weeks with:
# - NA counts in weeks 4, 12, 20, 21 and 22, so the windows that end in weeks
#   22, 23 and 24 have 2 rows left (rule 3);
# - counts of 0 in weeks 13 to 17, so the windows that end in weeks 16 and 17
#   have only zeros left (rule 2);
# - separated windows that end in weeks 15 and 18 (rule 4).
# The denominators rise by 6% a week, so the offset changes every slope.
# Location "b" has 15 weeks of a falling count.
v4t_series <- function() {
  set.seed(42)
  t26 <- 1:26
  a <- stats::rpois(
    26,
    30 * exp(0.12 * pmin(t26, 11) - 0.08 * pmax(t26 - 18, 0))
  )
  a[c(4, 12, 20, 21, 22)] <- NA
  a[13:17] <- 0
  b <- stats::rpois(15, 200 * exp(-0.1 * (1:15)))
  list(
    num = list(a = a, b = b),
    den = list(
      a = stats::rpois(26, 3000 * exp(0.06 * t26)),
      b = stats::rpois(15, 5000 * exp(0.04 * (1:15)))
    )
  )
}

# stats::glm() with summary() in every window of one series. Rows with an NA
# count or denominator leave the window. A window gets values only when glm
# fits it without a warning, at least 3 rows are left, and the counts above 0
# are not all at the first or the last row left. The result has one row per
# week.
v4t_glm <- function(y, den, width) {
  n <- length(y)
  out <- matrix(
    NA_real_,
    n,
    4,
    dimnames = list(NULL, c("beta1", "se", "p", "df"))
  )
  for (i in seq(width, n)) {
    rows <- seq(i - width + 1, i)
    d <- data.frame(y = y[rows], t = rows)
    if (!is.null(den)) {
      d$den <- den[rows]
    }
    d <- stats::na.omit(d)
    pos <- d$t[d$y > 0]
    if (
      nrow(d) < 3 ||
        !length(pos) ||
        max(pos) <= min(d$t) ||
        min(pos) >= max(d$t)
    ) {
      next
    }
    model <- if (is.null(den)) y ~ t else y ~ t + offset(log(den))
    s <- tryCatch(
      summary(stats::glm(model, family = stats::quasipoisson, data = d)),
      warning = function(w) NULL
    )
    if (!is.null(s)) {
      out[i, ] <- c(s$coefficients["t", c(1, 2, 4)], s$df.residual)
    }
  }
  out
}

# The rows of `ens` that belong to `loc`, in week order.
v4t_rows <- function(ens, loc) {
  which(ens$data$location_code == loc)
}

for (has_den in c(TRUE, FALSE)) {
  test_that(
    paste(
      "one draw equals stats::glm window by window,",
      if (has_den) "rate with offset" else "count with no offset"
    ),
    {
      s <- v4t_series()
      ens <- v4t_pass(s$num, s$den)
      out <- short_term_trend_v4(
        ens,
        measure = "numerator",
        width = 5,
        denominator = if (has_den) "denominator",
        name = "x",
        seed = 1
      )
      for (loc in c("a", "b")) {
        i <- v4t_rows(out, loc)
        g <- v4t_glm(
          s$num[[loc]],
          if (has_den) s$den[[loc]],
          width = 5
        )
        fitted <- !is.na(g[, "beta1"])
        b1 <- out$draws$x_trend_beta1[i, 1]
        se <- out$draws$x_trend_se[i, 1]
        # v4 has a slope in exactly the windows that glm fits.
        expect_identical(!is.na(b1), fitted, label = paste(loc, "fitted"))
        v4t_expect_close(b1, g[, "beta1"], paste(loc, "beta1"))
        v4t_expect_close(se, g[, "se"], paste(loc, "se"))
        p <- 2 * stats::pt(-abs(b1 / se), g[, "df"])
        v4t_expect_close(p, g[, "p"], paste(loc, "p"))
        # P(increasing) is pt(beta1 / se, df) with the glm values.
        v4t_expect_close(
          out$data$x_trend_pinc[i][fitted],
          stats::pt(g[fitted, "beta1"] / g[fitted, "se"], g[fitted, "df"]),
          paste(loc, "pinc")
        )
        # glm fits 15 of the 22 windows of "a", and all 11 windows of "b".
        expect_identical(
          sum(fitted),
          c(a = 15L, b = 11L)[[loc]],
          label = paste(loc, "glm windows")
        )
      }
    }
  )
}

test_that("rules 2 to 4 and the first width - 1 weeks give the v1 values", {
  s <- v4t_series()
  ens <- v4t_pass(s$num, s$den)
  for (den in list("denominator", NULL)) {
    out <- short_term_trend_v4(
      ens,
      measure = "numerator",
      width = 5,
      denominator = den,
      name = "x",
      seed = 1
    )
    i <- v4t_rows(out, "a")
    b1 <- out$draws$x_trend_beta1[i, 1]
    se <- out$draws$x_trend_se[i, 1]
    pinc <- out$data$x_trend_pinc[i]
    gr_cols <- c(
      "x_trend_gr",
      grep("^x_trend_gr_q", names(out$data), value = TRUE)
    )
    gr <- as.matrix(out$data[i, gr_cols, with = FALSE])
    # The first width - 1 weeks of both series: no window.
    for (loc in c("a", "b")) {
      j <- v4t_rows(out, loc)[1:4]
      expect_true(all(is.na(out$draws$x_trend_beta1[j, 1])))
      expect_true(all(is.na(out$data$x_trend_pinc[j])))
    }
    # Rule 3: the windows that end in weeks 22, 23 and 24 have 2 rows left.
    for (w in c(22, 23, 24)) {
      expect_true(is.na(b1[w]) && is.na(se[w]) && is.na(pinc[w]))
      expect_true(all(is.na(gr[w, ])))
    }
    # Rule 2: the windows that end in weeks 16 and 17 have only zeros left.
    for (w in c(16, 17)) {
      expect_identical(pinc[w], 0)
      expect_true(is.na(b1[w]) && is.na(se[w]))
      expect_true(all(is.na(gr[w, ])))
    }
    # Rule 4: the windows that end in weeks 15 and 18 are separated.
    for (w in c(15, 18)) {
      expect_true(is.na(b1[w]) && is.na(se[w]) && is.na(pinc[w]))
      expect_true(all(is.na(gr[w, ])))
    }
    # Every other window of "a" has values.
    other <- setdiff(5:26, c(15, 16, 17, 18, 22, 23, 24))
    expect_true(all(!is.na(b1[other]) & !is.na(pinc[other])))
  }
})

test_that("an all-zero window of width 2 gets pinc 0, and one with counts gets NA", {
  ens <- v4t_pass(
    list(a = c(5, 0, 0, NA, 0, 3, 4)),
    list(a = rep(100, 7))
  )
  out <- short_term_trend_v4(ens, "numerator", width = 2, name = "x", seed = 1)
  # Windows end in weeks 2 to 7: [5,0] has a count, [0,0] is all zero,
  # [0,NA] has 1 row left, [NA,0] has 1 row left, [0,3] and [3,4] have counts.
  expect_identical(out$data$x_trend_pinc, c(NA, NA, 0, NA, NA, NA, NA))
  expect_true(all(is.na(out$draws$x_trend_beta1)))
})

test_that("rule 4 gives NA where the kernel does not converge", {
  real_kernel <- .v4_rolling_qp_offset
  testthat::local_mocked_bindings(
    .v4_rolling_qp_offset = function(...) {
      k <- real_kernel(...)
      k$converged[!is.na(k$converged)] <- FALSE
      k
    },
    .package = "csalert"
  )
  s <- v4t_series()
  out <- short_term_trend_v4(
    v4t_pass(s$num, s$den),
    "numerator",
    width = 5,
    denominator = "denominator",
    name = "x",
    seed = 1
  )
  i <- v4t_rows(out, "a")
  expect_true(all(is.na(out$draws$x_trend_beta1)))
  expect_true(all(is.na(out$draws$x_trend_se)))
  # Rule 2 comes before rule 4.
  expect_identical(which(!is.na(out$data$x_trend_pinc[i])), c(16L, 17L))
  expect_identical(out$data$x_trend_pinc[i][16:17], c(0, 0))
})

test_that("a zero denominator becomes 1 before the log, as in v1", {
  s <- v4t_series()
  den0 <- s$den
  den0$b[8] <- 0
  den1 <- s$den
  den1$b[8] <- 1
  fit <- function(den) {
    short_term_trend_v4(
      v4t_pass(s$num, den),
      "numerator",
      width = 5,
      denominator = "denominator",
      name = "x",
      seed = 1
    )$draws$x_trend_beta1
  }
  b0 <- fit(den0)
  expect_identical(b0, fit(den1))
  expect_false(identical(b0, fit(s$den)))
})

# The pre-kernel v1 reference. fixtures/v1_reference.rds holds the output of
# the v1 method of csalert 94100f5, which fitted with glm2. The cells listed in
# fixtures/v1_reference_changes.md were rerun on the kernel, so they are left
# out. The fixture holds the status and the doubling days, rounded to 0.1 days.
# It holds no slope, standard error or p-value, so the comparison is:
# - status: identical, from the v4 slope and the p-value from v4's beta1 / se;
# - doubling days: v1's (N + F) * log(2) / beta1_v1 * 7 with the v4 slope
#   converted to v1's time scale, row / (N + F), is within 0.05 days of the
#   stored value. That is the rounding of the stored value, plus 1e-6 days.
v4t_v1 <- readRDS(test_path("fixtures", "v1_reference.rds"))
V4T_DD_TOL <- 0.05 + 1e-6

# The cells of the table "Every changed cell": case, column and row.
v4t_changed_cells <- function() {
  lines <- readLines(test_path("fixtures", "v1_reference_changes.md"))
  start <- grep("^## Every changed cell", lines)
  rows <- lines[seq(start + 1, length(lines))]
  rows <- rows[grepl("^\\| [a-z0-9_]+ \\| [a-z0-9_]+ \\| [0-9]+ \\|", rows)]
  parts <- strsplit(rows, "|", fixed = TRUE)
  field <- function(k) trimws(vapply(parts, `[`, "", k))
  data.frame(
    case = field(2),
    column = field(3),
    row = as.integer(field(4))
  )
}
v4t_changed <- v4t_changed_cells()

test_that("the list of changed v1 cells parses to its 830 cells", {
  expect_identical(nrow(v4t_changed), 830L)
})

# Cases that are not compared, and why:
# - forecast0: v1 stopped, so there is no output;
# - missing_week: v1's windows are rows, and week 2020-10 is missing, so its
#   windows are not those of a series with one row per week;
# - last_window_na_noden, width2_allzero_den and width2_allzero_noden: the
#   whole stored output is from the kernel version, not from glm2.
V4T_SKIP <- c(
  "forecast0_den",
  "forecast0_noden",
  "missing_week_den",
  "missing_week_noden",
  "last_window_na_noden",
  "width2_allzero_den",
  "width2_allzero_noden"
)

# The number of rows left in each window: rows with a count, and with a
# denominator for a rate. NA for the first width - 1 rows of each series.
v4t_n_used <- function(ens, has_den, width) {
  ok <- !is.na(ens$draws$numerator[, 1])
  if (has_den) {
    ok <- ok & !is.na(ens$draws$denominator[, 1])
  }
  out <- rep(NA_real_, length(ok))
  for (loc in unique(ens$data$location_code)) {
    i <- v4t_rows(ens, loc)
    for (m in seq(width, length(i))) {
      out[i[m]] <- sum(ok[i[seq(m - width + 1, m)]])
    }
  }
  out
}

v4t_v1_compare <- function(case_name) {
  case <- v4t_v1$cases[[case_name]]
  a <- case$args
  has_den <- !is.null(a[["denominator"]])
  width <- a$trend_isoyearweeks
  input <- case$input
  ens <- v4t_pass_dt(data.table::data.table(
    location_code = input$location_code,
    isoyearweek = input$isoyearweek,
    numerator = input$numerator_n,
    denominator = input$denominator_n
  ))
  # The passthrough has one row per input row, so its windows are v1's.
  expect_identical(nrow(ens$data), nrow(input))
  out <- short_term_trend_v4(
    ens,
    "numerator",
    width = width,
    denominator = if (has_den) "denominator",
    name = "x",
    seed = 1
  )
  b1 <- out$draws$x_trend_beta1[, 1]
  se <- out$draws$x_trend_se[, 1]
  pinc <- out$data$x_trend_pinc
  df <- v4t_n_used(out, has_den, width) - 2
  p <- 2 * stats::pt(-abs(b1 / se), df)
  # v1's time is row / (N + F): N rows of the series and F forecast weeks.
  n_f <- table(input$location_code)[out$data$location_code] +
    a$forecast_isoyearweeks
  n_f <- as.numeric(n_f)
  b1_v1 <- b1 * n_f
  status <- if (a$include_decreasing) {
    ifelse(p > a$alpha, "null", ifelse(b1 < 0, "decreasing", "increasing"))
  } else {
    ifelse(p <= a$alpha & b1 > 0, "increasing", "notincreasing")
  }
  zero_status <- if (a$include_decreasing) "null" else "notincreasing"
  status[is.na(b1) & pinc %in% 0] <- zero_status
  doubling <- n_f * log(2) / b1_v1 * 7

  ref <- case$output
  at <- match(
    paste(ref$location_code, ref$isoyearweek),
    paste(out$data$location_code, out$data$isoyearweek)
  )
  status_col <- grep("_status$", names(ref), value = TRUE)
  dd_col <- grep("_doublingdays0_", names(ref), value = TRUE)
  ref_status <- as.character(ref[[status_col]])
  compare <- !is.na(at) & !ref_status %in% c("training", "forecast")
  changed <- v4t_changed[v4t_changed$case == case_name, ]
  keep_status <- compare &
    !seq_along(at) %in% changed$row[changed$column == status_col]
  keep_dd <- compare & !seq_along(at) %in% changed$row[changed$column == dd_col]

  expect_identical(
    status[at[keep_status]],
    ref_status[keep_status],
    label = paste(case_name, "status")
  )
  got <- doubling[at[keep_dd]]
  want <- ref[[dd_col]][keep_dd]
  expect_identical(
    is.na(got),
    is.na(want),
    label = paste(case_name, "NA doubling days")
  )
  gap <- abs(got - want)
  bad <- which(!is.na(gap) & gap > V4T_DD_TOL)
  expect(
    length(bad) == 0,
    sprintf(
      "%s: doubling days differ by more than 0.05 in %d rows: %s vs %s",
      case_name,
      length(bad),
      paste(utils::head(got[bad]), collapse = ", "),
      paste(utils::head(want[bad]), collapse = ", ")
    )
  )
  c(status = sum(keep_status), doubling = sum(keep_dd & !is.na(ref[[dd_col]])))
}

v4t_v1_counts <- list()
for (case_name in setdiff(names(v4t_v1$cases), V4T_SKIP)) {
  test_that(paste("one draw equals the pre-kernel v1 reference:", case_name), {
    v4t_v1_counts[[case_name]] <<- v4t_v1_compare(case_name)
  })
}

test_that("the v1 comparison covers 36 cases and their unchanged cells", {
  counts <- do.call(rbind, v4t_v1_counts)
  expect_identical(nrow(counts), 36L)
  # The status cells compared, and the doubling-day cells with a stored value.
  expect_identical(sum(counts[, "status"]), 3801L)
  expect_identical(sum(counts[, "doubling"]), 3015L)
})

test_that("with one draw, the growth-rate percentiles are in closed form", {
  s <- v4t_series()
  out <- short_term_trend_v4(
    v4t_pass(s$num, s$den),
    "numerator",
    width = 5,
    denominator = "denominator",
    name = "x",
    seed = 1
  )
  i <- v4t_rows(out, "a")
  g <- v4t_glm(s$num$a, s$den$a, width = 5)
  probs <- c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975)
  labels <- c(
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
  for (k in seq_along(probs)) {
    want <- 100 *
      (exp(g[, "beta1"] + g[, "se"] * stats::qt(probs[k], g[, "df"])) - 1)
    v4t_expect_close(
      out$data[[paste0("x_trend_gr_", labels[k])]][i],
      want,
      labels[k]
    )
  }
  v4t_expect_close(
    out$data$x_trend_gr[i],
    100 * (exp(g[, "beta1"]) - 1),
    "median"
  )
})

# Many draws: 12 weeks, 2000 draws of a rising count, width 5.
v4t_many <- function() {
  set.seed(7)
  d <- data.table::data.table(
    location_code = "a",
    isoyearweek = sprintf("2023-%02d", 1:12)
  )
  mu <- 20 * exp(0.08 * (1:12))
  csfmt_ensemble_v4(
    d,
    id_cols = "location_code",
    draws = list(num = matrix(stats::rpois(12 * 2000, mu), 12))
  )
}

test_that("with many draws, every draw equals stats::glm in a sample of draws", {
  ens <- v4t_many()
  out <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  for (j in c(1, 2, 999, 1000, 1999, 2000)) {
    g <- v4t_glm(ens$draws$num[, j], NULL, width = 5)
    v4t_expect_close(
      out$draws$x_trend_beta1[, j],
      g[, "beta1"],
      paste("beta1 draw", j)
    )
    v4t_expect_close(out$draws$x_trend_se[, j], g[, "se"], paste("se draw", j))
  }
})

test_that("the draws give the same fit in one kernel call or in chunks", {
  ens <- v4t_many()
  one <- .v4_trend_fit(
    ens$draws$num,
    NULL,
    ens$data$time_series_id,
    ens$data$time_series_internal_id,
    5
  )
  # 12 rows and 1 series: chunks of 7 draws, the last one of 5.
  chunked <- .v4_trend_fit(
    ens$draws$num,
    NULL,
    ens$data$time_series_id,
    ens$data$time_series_internal_id,
    5,
    chunk_cells = 7 * 12
  )
  expect_identical(chunked, one)
})

test_that("with many draws, pinc is the mean of pt(beta1 / se, df) and matches a simulation", {
  ens <- v4t_many()
  out <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  b1 <- out$draws$x_trend_beta1
  se <- out$draws$x_trend_se
  rows <- 5:12
  expect_true(all(!is.na(b1[rows, ])))
  # Exact: df = 5 - 2 = 3 in every window.
  want <- rowMeans(stats::pt(b1 / se, 3))
  v4t_expect_close(out$data$x_trend_pinc[rows], want[rows], "pinc")
  # Brute force: 200 t draws per ensemble draw, 400,000 per week. The
  # tolerance is 5 binomial standard errors.
  set.seed(11)
  n_t <- 200
  for (w in rows) {
    sim <- rep(b1[w, ], n_t) + rep(se[w, ], n_t) * stats::rt(2000 * n_t, 3)
    bf <- mean(sim > 0)
    tol <- 5 * sqrt(bf * (1 - bf) / (2000 * n_t))
    expect_lte(abs(out$data$x_trend_pinc[w] - bf), tol)
  }
})

test_that("with many draws, the growth-rate percentiles match a simulation", {
  ens <- v4t_many()
  out <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  b1 <- out$draws$x_trend_beta1
  se <- out$draws$x_trend_se
  probs <- c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975)
  labels <- c(
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
  q_v4 <- as.matrix(out$data[, paste0("x_trend_gr_", labels), with = FALSE])
  # Exact: one t draw per ensemble draw, in column order, after set.seed(3).
  set.seed(3)
  t_draw <- matrix(stats::rt(8 * 2000, 3), 8)
  G <- 100 * (exp(b1[5:12, ] + se[5:12, ] * t_draw) - 1)
  want <- t(apply(G, 1, stats::quantile, probs = probs, names = FALSE))
  v4t_expect_close(unname(q_v4[5:12, ]), want, "percentiles")
  v4t_expect_close(
    out$data$x_trend_gr[5:12],
    apply(G, 1, stats::median),
    "median"
  )
  # Brute force: 200 t draws per ensemble draw. At each v4 percentile q_p, the
  # simulated share at or below q_p is within 5 standard errors,
  # 5 * sqrt(p * (1 - p) / 2000), of p.
  set.seed(12)
  n_t <- 200
  for (w in 5:12) {
    sim <- rep(b1[w, ], n_t) + rep(se[w, ], n_t) * stats::rt(2000 * n_t, 3)
    gr_sim <- 100 * (exp(sim) - 1)
    share <- vapply(q_v4[w, ], function(q) mean(gr_sim <= q), numeric(1))
    expect_true(all(abs(share - probs) <= 5 * sqrt(probs * (1 - probs) / 2000)))
  }
})

test_that("the trend does not change .Random.seed, and a seed gives the same result", {
  ens <- v4t_many()
  set.seed(21)
  before <- get(".Random.seed", envir = globalenv())
  one <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  # identical() inside expect_true(): testthat cannot print a diff of two
  # .Random.seed vectors.
  expect_true(identical(get(".Random.seed", envir = globalenv()), before))
  two <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  expect_identical(two$data, one$data)
  expect_identical(two$draws, one$draws)
  other <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 4)
  expect_false(identical(
    other$data$x_trend_gr_q02x5,
    one$data$x_trend_gr_q02x5
  ))
  expect_identical(other$data$x_trend_pinc, one$data$x_trend_pinc)

  env <- globalenv()
  saved <- get(".Random.seed", envir = env)
  rm(".Random.seed", envir = env)
  short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  absent <- !exists(".Random.seed", envir = env, inherits = FALSE)
  assign(".Random.seed", saved, envir = env)
  expect_true(absent)
})

test_that("a rerun with the same name replaces the columns and draws", {
  ens <- v4t_many()
  first <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  rerun <- short_term_trend_v4(first, "num", width = 4, name = "x", seed = 3)
  fresh <- short_term_trend_v4(ens, "num", width = 4, name = "x", seed = 3)
  # Width 4 and width 5 give other values, so a column left from the first
  # run is visible.
  expect_false(identical(first$data$x_trend_pinc, fresh$data$x_trend_pinc))
  expect_false(identical(first$data$x_trend_gr, fresh$data$x_trend_gr))
  # Each name appears once, in the order of a single run.
  expect_identical(anyDuplicated(names(rerun$data)), 0L)
  expect_identical(anyDuplicated(names(rerun$draws)), 0L)
  expect_identical(names(rerun$data), names(fresh$data))
  expect_identical(names(rerun$draws), names(fresh$draws))
  # Every column holds the values of the second run.
  for (col in setdiff(names(fresh$data), names(ens$data))) {
    expect_identical(rerun$data[[col]], fresh$data[[col]], label = col)
  }
  expect_identical(rerun$draws, fresh$draws)
  # The input ensemble is not changed.
  expect_identical(names(ens$data), names(v4t_many()$data))
})

test_that("the 63-byte check of the new names runs before the fit", {
  # The fit stops, so only the name check can give the 63-byte error.
  testthat::local_mocked_bindings(
    .v4_trend_fit = function(...) stop("the fit ran", call. = FALSE),
    .package = "csalert"
  )
  ens <- v4t_many()
  # 52 bytes + "_trend_beta1" is 64 bytes.
  expect_error(
    short_term_trend_v4(
      ens,
      "num",
      width = 5,
      name = strrep("n", 52),
      seed = 3
    ),
    "longer than 63 bytes"
  )
  # 49 bytes + "_trend_gr_q02x5" is 64 bytes.
  expect_error(
    short_term_trend_v4(
      ens,
      "num",
      width = 5,
      name = strrep("n", 49),
      seed = 3
    ),
    "longer than 63 bytes"
  )
  expect_error(
    short_term_trend_v4(
      ens,
      "num",
      width = 5,
      name = strrep("n", 48),
      seed = 3
    ),
    "the fit ran"
  )
})

test_that("short_term_trend_v4 is exported", {
  ns_file <- file.path(system.file(package = "csalert"), "NAMESPACE")
  expect_true(file.exists(ns_file))
  expect_true("export(short_term_trend_v4)" %in% trimws(readLines(ns_file)))
})

# 10 weeks of one series, with 50 draws, from `first`.
v4t_grid <- function(first, drop = integer()) {
  cal <- cstime::dates_by_isoyearweek
  weeks <- cal$isoyearweek[match(first, cal$isoyearweek) + 0:9]
  keep <- setdiff(seq_along(weeks), drop)
  set.seed(5)
  csfmt_ensemble_v4(
    data.table::data.table(location_code = "a", isoyearweek = weeks[keep]),
    id_cols = "location_code",
    draws = list(
      num = matrix(stats::rpois(length(keep) * 50, 30), length(keep))
    )
  )
}

test_that("a missing ISO week is an error that names the series and the gap", {
  # 2023-05 is missing.
  expect_error(
    short_term_trend_v4(
      v4t_grid("2023-01", drop = 5),
      "num",
      width = 3,
      seed = 1
    ),
    "series location_code=a is not one row per ISO week: 2023-04 is followed by 2023-06",
    fixed = TRUE
  )
  # A gap across the new year: 2021-01 is missing after 2020-53.
  expect_error(
    short_term_trend_v4(
      v4t_grid("2020-50", drop = 5),
      "num",
      width = 3,
      seed = 1
    ),
    "2020-53 is followed by 2021-02",
    fixed = TRUE
  )
  # A complete grid across 2020-53, a 53-week year, has no error.
  out <- short_term_trend_v4(v4t_grid("2020-50"), "num", width = 3, seed = 1)
  expect_identical(sum(!is.na(out$data$num_trend_pinc)), 8L)
})

test_that("a time column that is not an ISO week is an error", {
  ens <- v4t_grid("2023-01")
  ens$data$isoyearweek[3] <- "2023-W03"
  expect_error(
    short_term_trend_v4(ens, "num", width = 3, seed = 1),
    "must hold ISO weeks"
  )
})

test_that("the new names are those of the 9 percentiles, and each is checked", {
  ens <- v4t_many()
  out <- short_term_trend_v4(ens, "num", width = 5, name = "x", seed = 3)
  expect_identical(
    setdiff(names(out$data), names(ens$data)),
    c(
      "x_trend_pinc",
      "x_trend_gr",
      "x_trend_gr_q02x5",
      "x_trend_gr_q05x0",
      "x_trend_gr_q10x0",
      "x_trend_gr_q25x0",
      "x_trend_gr_q50x0",
      "x_trend_gr_q75x0",
      "x_trend_gr_q90x0",
      "x_trend_gr_q95x0",
      "x_trend_gr_q97x5"
    )
  )
  expect_identical(
    setdiff(names(out$draws), names(ens$draws)),
    c("x_trend_beta1", "x_trend_se")
  )
  # 52 bytes + "_trend_beta1" is 64 bytes.
  expect_error(
    short_term_trend_v4(
      ens,
      "num",
      width = 5,
      name = strrep("n", 52),
      seed = 3
    ),
    "longer than 63 bytes"
  )
  # 49 bytes: only "_trend_gr_q02x5" and the other percentiles reach 64.
  expect_error(
    short_term_trend_v4(
      ens,
      "num",
      width = 5,
      name = strrep("n", 49),
      seed = 3
    ),
    "longer than 63 bytes"
  )
  expect_no_error(
    short_term_trend_v4(ens, "num", width = 5, name = strrep("n", 48), seed = 3)
  )
  expect_error(
    short_term_trend_v4(ens, "num", width = 5, name = "x_hlm", seed = 3),
    "reserved suffix"
  )
})

test_that("short_term_trend_v4 checks its arguments", {
  ens <- v4t_many()
  expect_error(short_term_trend_v4(ens, "num", width = 5, name = "x"), "seed")
  expect_error(
    short_term_trend_v4(ens, "nope", width = 5, seed = 1),
    "must each name one matrix"
  )
  expect_error(
    short_term_trend_v4(ens, "num", width = 5, denominator = "nope", seed = 1),
    "must each name one matrix"
  )
  expect_error(short_term_trend_v4(ens, "num", width = 1, seed = 1), "width")
  expect_error(short_term_trend_v4(ens, "num", width = 2.5, seed = 1), "width")
})

test_that("the one-draw growth percentiles call qt once per df, with the same values", {
  # The reference is the per-row form of 2026.10.22: stats::qt(p, df) for
  # every row. Rows share df 1, 2 and 3, and two rows have no fit.
  set.seed(8)
  n <- 12L
  fit <- list(
    beta1 = matrix(stats::rnorm(n, 0, 0.1), n, 1),
    se = matrix(stats::runif(n, 0.01, 0.2), n, 1),
    df = matrix(c(1, 2, 3, NA, 1, 2, 3, 3, NA, 2, 1, 1), n, 1)
  )
  fit$beta1[c(4, 9), 1] <- NA_real_
  fit$se[c(4, 9), 1] <- NA_real_
  ref_q <- matrix(
    vapply(
      .V4_PROBS,
      function(p) {
        return(
          100 *
            (exp(fit$beta1[, 1] + fit$se[, 1] * stats::qt(p, fit$df[, 1])) - 1)
        )
      },
      numeric(n)
    ),
    n,
    length(.V4_PROBS)
  )
  ref_med <- 100 *
    (exp(fit$beta1[, 1] + fit$se[, 1] * stats::qt(0.5, fit$df[, 1])) - 1)
  g <- .v4_trend_growth(fit)
  expect_identical(g$q, ref_q)
  expect_identical(g$median, ref_med)

  # Every df NA: NA rows, not an error.
  fit$df[] <- NA_real_
  g <- .v4_trend_growth(fit)
  expect_identical(g$median, rep(NA_real_, n))
  expect_identical(g$q, matrix(NA_real_, n, length(.V4_PROBS)))
})
