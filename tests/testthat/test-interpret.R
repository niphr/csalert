# csfmt_interpret: dataset-level grammar interpretation.

test_that("interprets value columns and excludes structural ones", {
  d <- data.table::data.table(
    location_code = "norge", isoyearweek = "2024-10", indicator_tag = "flu",
    numerator_nowcasted_q50x0 = 5,
    numerator_nowcasted_trend_gr_q02x5 = -1,
    numerator_nowcasted_status_q50x0 = 3L,
    numerator_nowcasted_status_prob_high = 0.2,
    mem_high = 12
  )
  cat <- csfmt_interpret(d)

  # structural columns are excluded
  expect_false(any(c("location_code", "isoyearweek", "indicator_tag") %in% cat$column))

  # quantile column -> q coordinate, no level
  r1 <- cat[column == "numerator_nowcasted_q50x0"]
  expect_equal(r1$q, 0.5); expect_true(is.na(r1$level)); expect_true(r1$interpretable)

  # status quantile -> role status, q coordinate
  r2 <- cat[column == "numerator_nowcasted_status_q50x0"]
  expect_equal(r2$role, "status"); expect_equal(r2$q, 0.5)

  # status level probability -> level coordinate
  r3 <- cat[column == "numerator_nowcasted_status_prob_high"]
  expect_equal(r3$level, "high")
})
