# compare_results / qc_week_over_week.

mk_run <- function(weeks, vals, status) {
  data.table::data.table(
    time_series_id = "abc", indicator_tag = "flu", isoyearweek = weeks,
    numerator_nowcasted_q50x0 = vals,
    numerator_nowcasted_status_q50x0 = status
  )
}

test_that("A is empty when settled weeks agree; B captures frontier transitions", {
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2024-10"); w <- weeks[i0:(i0 + 5)]

  prev <- mk_run(w[1:5], vals = c(10, 11, 12, 13, 14), status = c(1, 1, 2, 2, 3))
  curr <- mk_run(w[1:6], vals = c(10, 11, 12, 13, 15, 16), status = c(1, 1, 2, 2, 2, 3))

  qc <- qc_week_over_week(curr, prev, max_delay = 2)

  # settled weeks (w1..w3) identical -> integrity tripwire empty
  expect_equal(nrow(qc$integrity), 0)

  # frontier: w5 status changed (3->2), w6 is new
  expect_equal(nrow(qc$signal), 2)
  expect_equal(qc$signal[isoyearweek == w[6]]$change, "new")
  s5 <- qc$signal[isoyearweek == w[5]]
  expect_equal(s5$change, "changed")
  expect_equal(s5$from, 3); expect_equal(s5$to, 2)
})

test_that("A flags an unexpected revision to a settled week", {
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2024-10"); w <- weeks[i0:(i0 + 5)]

  prev <- mk_run(w[1:5], vals = c(10, 11, 12, 13, 14), status = c(1, 1, 2, 2, 3))
  curr <- mk_run(w[1:6], vals = c(10, 99, 12, 13, 15, 16), status = c(1, 1, 2, 2, 2, 3))  # w2 revised

  qc <- qc_week_over_week(curr, prev, max_delay = 2)
  expect_equal(nrow(qc$integrity), 1)
  expect_equal(qc$integrity$isoyearweek, w[2])
  expect_equal(qc$integrity$prv, 11); expect_equal(qc$integrity$cur, 99)
})
