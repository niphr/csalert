# The shared v4 helpers are copies of v3 or v1 helpers, so they MUST give the
# same result.

test_that(".v4_isoyearweek_week_start matches isoyearweek_week_start", {
  x <- c("2026-01", "2020-53", "2023-30", "2026-99", NA)
  expect_identical(.v4_isoyearweek_week_start(x), isoyearweek_week_start(x))
  expect_equal(.v4_isoyearweek_week_start("2026-01"), as.Date("2025-12-29"))
})

test_that(".v4_set_time_series_id matches set_time_series_id", {
  d <- data.table::data.table(
    location_code = c("nation", "nation", "county03"),
    age = c("total", "0-4", "total"),
    x = 1:3
  )
  a <- data.table::copy(d)
  b <- data.table::copy(d)
  .v4_set_time_series_id(a, c("location_code", "age"))
  set_time_series_id(b, c("location_code", "age"))
  expect_identical(a, b)
})

test_that(".v4_row_mean and .v4_row_sd match row_mean and row_sd", {
  set.seed(1)
  m <- matrix(stats::rnorm(40), 8)
  m[2, 3] <- NA
  for (na in c(FALSE, TRUE)) {
    expect_identical(
      .v4_row_mean(m, na.rm = na),
      csalert:::row_mean(m, na.rm = na)
    )
    expect_identical(.v4_row_sd(m, na.rm = na), csalert:::row_sd(m, na.rm = na))
  }
})

test_that("the MEM helpers match the v3 MEM helpers", {
  w <- cstime::dates_by_isoyearweek$isoyearweek
  iyw <- w[match("2015-30", w) + 0:(52 * 7 - 1)]
  set.seed(2)
  lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
  d <- data.table::data.table(
    time_series_id = "a",
    season = cstime::isoyearweek_to_season_c(iyw),
    seasonweek = cstime::isoyearweek_to_seasonweek_n(iyw),
    point = as.numeric(stats::rpois(length(iyw), lam))
  )
  args <- list(d, 2, 5, 10, 30, "2018/2019")
  v4 <- do.call(.v4_mem_estimate_thresholds, args)
  v3 <- do.call(csalert:::mem_estimate_thresholds, args)
  expect_identical(v4, v3)
  expect_gt(length(v4$thr_all), 2L)
  expect_gt(length(v4$provisional), 0L)
  expect_identical(
    .v4_mem_estimate_thresholds(d, 2, 5, 10, 30, NULL),
    csalert:::mem_estimate_thresholds(d, 2, 5, 10, 30, NULL)
  )
  # fewer than 2 seasons with a count above 0 give no fit
  zero <- data.frame(a = rep(0, 30), b = rep(0, 30), c = 1:30)
  expect_null(.v4_mem_fit(zero))
  expect_null(.v4_mem_fit(NULL))
})

test_that(".v4_collapse_status_into matches collapse_status_into", {
  set.seed(3)
  M <- matrix(sample(c(1:5, NA), 6 * 40, replace = TRUE), nrow = 6)
  levs <- c("preepidemic", "low", "medium", "high", "veryhigh")
  probs <- c(0.05, 0.5, 0.95)
  a <- data.table::data.table(isoyearweek = sprintf("2023-%02d", 1:6))
  b <- data.table::copy(a)
  .v4_collapse_status_into(a, "cases_mem", M, levs, probs)
  csalert:::collapse_status_into(b, "cases_mem", M, levs, probs)
  expect_identical(a, b)
  expect_true("cases_mem_prob_veryhigh" %in% names(a))
})
