# csfmt_ensemble_v3 container: invariants and validation.

mk <- function(...) data.table::data.table(...)
ID <- c("indicator", "location", "age")

test_that("constructor assigns ids, internal ids, and sorts by time within series", {
  d <- mk(indicator = "flu", location = "nation", age = "total",
          isoyearweek = c("2020-03", "2020-01", "2020-02"), value = c(3, 1, 2))
  ens <- csfmt_ensemble_v3(d, id_cols = ID)

  expect_s3_class(ens, "csfmt_ensemble_v3")
  expect_true(all(c("time_series_id", "time_series_label", "time_series_internal_id")
                  %in% names(ens$data)))
  expect_equal(ens$data$isoyearweek, c("2020-01", "2020-02", "2020-03"))
  expect_equal(ens$data$time_series_internal_id, 1:3)
})

test_that("time_series_id is a content hash: same strata -> same id across objects", {
  d1 <- mk(indicator = "flu", location = "nation", age = "total",
           isoyearweek = "2020-01", value = 1)
  d2 <- mk(indicator = "flu", location = "nation", age = "total",
           isoyearweek = "2021-50", value = 9)
  e1 <- csfmt_ensemble_v3(d1, id_cols = ID)
  e2 <- csfmt_ensemble_v3(d2, id_cols = ID)
  expect_equal(e1$data$time_series_id, e2$data$time_series_id)
})

test_that("different strata -> different id; internal ids restart per series", {
  d <- mk(indicator = rep(c("flu", "rsv"), each = 2), location = "nation", age = "total",
          isoyearweek = rep(c("2020-01", "2020-02"), 2), value = 1:4)
  ens <- csfmt_ensemble_v3(d, id_cols = ID)
  expect_equal(data.table::uniqueN(ens$data$time_series_id), 2L)
  expect_equal(ens$data[, max(time_series_internal_id), by = time_series_id]$V1, c(2L, 2L))
})

test_that("validate rejects a misaligned draw matrix", {
  d <- mk(indicator = "flu", location = "nation", age = "total",
          isoyearweek = c("2020-01", "2020-02"), value = c(1, 2))
  bad <- list(value = matrix(1:15, nrow = 3))   # 3 rows != 2
  expect_error(csfmt_ensemble_v3(d, id_cols = ID, draws = bad), "rows")
})

test_that("aligned draws are accepted and reordered to the canonical sort", {
  d <- mk(indicator = "flu", location = "nation", age = "total",
          isoyearweek = c("2020-03", "2020-01", "2020-02"), value = c(30, 10, 20))
  # draws in INPUT order; row r corresponds to input row r
  M <- matrix(c(30, 31, 10, 11, 20, 21), nrow = 3, byrow = TRUE)  # col-pairs per week
  ens <- csfmt_ensemble_v3(d, id_cols = ID, draws = list(value = M))
  expect_equal(nrow(ens$draws$value), nrow(ens$data))
  # after sort weeks are 01,02,03 -> draw rows should follow (10,11),(20,21),(30,31)
  expect_equal(ens$draws$value[, 1], c(10, 20, 30))
})

test_that("print method runs", {
  d <- mk(indicator = "flu", location = "nation", age = "total",
          isoyearweek = "2020-01", value = 1)
  expect_output(print(csfmt_ensemble_v3(d, id_cols = ID)), "csfmt_ensemble_v3")
})
