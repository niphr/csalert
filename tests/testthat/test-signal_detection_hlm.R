# signal_detection_hlm (historical-limits seasonal baseline).

test_that("returns the status factor with the expected levels", {
  set.seed(1)
  d <- gen_weekly_skeleton(2015:2023)
  d[, cases_n := stats::rpois(.N, 10)]
  res <- csalert::signal_detection_hlm(d, value = "cases_n", baseline_isoyears = 3)

  expect_s3_class(res, "csfmt_rts_data_v1")
  expect_true("cases_n_status" %in% names(res))
  expect_s3_class(res$cases_n_status, "factor")
  expect_setequal(levels(res$cases_n_status),
                  c("training", "forecast", "null", "high"))
})

test_that("a large spike above the historical baseline is flagged high", {
  set.seed(1)
  d <- gen_weekly_skeleton(2015:2023)
  d[, cases_n := stats::rpois(.N, 10)]
  spike_week <- max(d$isoyearweek)
  d[isoyearweek == spike_week, cases_n := 1000L]

  res <- csalert::signal_detection_hlm(d, value = "cases_n", baseline_isoyears = 3)
  expect_equal(as.character(res[isoyearweek == spike_week]$cases_n_status), "high")
})

test_that("baseline prediction-interval columns are produced", {
  set.seed(1)
  d <- gen_weekly_skeleton(2015:2023)
  d[, cases_n := stats::rpois(.N, 10)]
  res <- csalert::signal_detection_hlm(d, value = "cases_n", baseline_isoyears = 3)
  expect_true(any(grepl("_baseline_predinterval_q50x0_n$", names(res))))
  expect_true(any(grepl("_baseline_predinterval_q99x5_n$", names(res))))
})
