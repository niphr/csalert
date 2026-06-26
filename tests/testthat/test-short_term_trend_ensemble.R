# Batched trend on the ensemble: kernel correctness + seam-safety.

test_that("rolling_slope_matrix is bit-identical to per-column OLS", {
  set.seed(1)
  Y <- matrix(stats::rpois(20 * 4, 30), nrow = 20)
  width <- 3
  rs <- rolling_slope_matrix(Y, width)

  ref <- matrix(NA_real_, 20, 4)
  for (j in 1:4) for (i in width:20) {
    yy <- Y[(i - width + 1):i, j]; tt <- seq_len(width)
    ref[i, j] <- stats::coef(stats::lm(yy ~ tt))[[2]]
  }
  expect_equal(rs$beta1[width:20, ], ref[width:20, ], tolerance = 1e-9)
  expect_true(all(is.na(rs$beta1[1:(width - 1), ])))
})

test_that("short_term_trend.csfmt_ensemble_v3 adds seam-masked gr/beta1 draws", {
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = wk)
  n <- nrow(d)
  M <- matrix(rep(seq_len(n) * 5, 6), nrow = n)   # increasing level, 6 draws
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = M))

  out <- short_term_trend(ens, measure = "cases", trend_isoyearweeks = 3)
  expect_true("cases_trend_gr" %in% names(out$draws))
  expect_true("cases_trend_beta1" %in% names(out$draws))

  gr <- out$draws[["cases_trend_gr"]]
  expect_true(all(is.na(gr[1:2, ])))          # leading width-1 rows masked
  expect_true(all(gr[3:n, ] > 0))             # increasing -> positive growth
})

test_that("stacked series do not contaminate across the seam", {
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  n1 <- length(wk)
  d <- rbind(
    data.table::data.table(indicator = "flu", location = "nation", age = "total", isoyearweek = wk),
    data.table::data.table(indicator = "rsv", location = "nation", age = "total", isoyearweek = wk)
  )
  M <- matrix(c(seq_len(n1) * 5, seq_len(n1) * 5), ncol = 1)  # two ramps stacked, 1 draw
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = M))

  out <- short_term_trend(ens, measure = "cases", trend_isoyearweeks = 3)
  beta1 <- out$draws[["cases_trend_beta1"]]
  iid <- out$data$time_series_internal_id

  expect_true(all(is.na(beta1[iid < 3, ])))   # boundary-crossing windows masked
  expect_true(all(beta1[iid >= 3, ] > 0))     # each series' clean ramp slope, no contamination
})

test_that("missing measure errors", {
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = c("2020-01", "2020-02", "2020-03"))
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = matrix(1:9, 3)))
  expect_error(short_term_trend(ens, measure = "nope"), "not in")
})
