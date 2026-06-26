# short_term_trend (Benedetti 2019 quasipoisson GLM trend).

test_that("returns a csfmt with the dynamically-named trend status factor", {
  d <- gen_weekly_skeleton(2020)
  d[, cases_n := seq_len(.N) * 3L]
  res <- csalert::short_term_trend(d, numerator = "cases_n", trend_isoyearweeks = 6)

  expect_s3_class(res, "csfmt_rts_data_v1")
  status_col <- grep("_trend0_.*_status$", names(res), value = TRUE)
  expect_length(status_col, 1)
  expect_s3_class(res[[status_col]], "factor")
  expect_setequal(levels(res[[status_col]]),
                  c("training", "forecast", "notincreasing", "increasing"))
})

test_that("a clearly increasing series is detected as increasing", {
  d <- gen_weekly_skeleton(2020)
  d[, cases_n := seq_len(.N) * 3L]               # monotonically increasing
  res <- csalert::short_term_trend(d, numerator = "cases_n", trend_isoyearweeks = 6)
  status_col <- grep("_trend0_.*_status$", names(res), value = TRUE)
  expect_true("increasing" %in% as.character(res[[status_col]]))
})

test_that("a flat series is never flagged increasing", {
  d <- gen_weekly_skeleton(2020)
  d[, cases_n := 50L]
  res <- csalert::short_term_trend(d, numerator = "cases_n", trend_isoyearweeks = 6)
  status_col <- grep("_trend0_.*_status$", names(res), value = TRUE)
  expect_false("increasing" %in% as.character(res[[status_col]]))
})

test_that("forecast + prediction-interval + doubling-days columns are produced", {
  d <- gen_weekly_skeleton(2020)
  d[, cases_n := seq_len(.N) * 3L]
  res <- csalert::short_term_trend(d, numerator = "cases_n", trend_isoyearweeks = 6)
  expect_true(any(grepl("_forecasted_n$", names(res))))
  expect_true(any(grepl("_predinterval_q02x5_n$", names(res))))
  expect_true(any(grepl("_predinterval_q97x5_n$", names(res))))
  expect_true(any(grepl("_doublingdays0_", names(res))))
})
