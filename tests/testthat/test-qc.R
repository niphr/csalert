# qc_surveillance_data: generic input checks (verdict only, no flow/policy).

test_that("flags empty data", {
  v <- qc_surveillance_data(data.table::data.table(isoyearweek_reference = character()))
  expect_false(v$ok)
  expect_match(v$reasons, "no data")
})

test_that("passes fresh, present data", {
  d <- data.table::data.table(isoyearweek_reference = c("2024-10", "2024-11"))
  v <- qc_surveillance_data(d, expect_latest = "2024-11")
  expect_true(v$ok)
  expect_length(v$reasons, 0)
})

test_that("flags a stale feed", {
  d <- data.table::data.table(isoyearweek_reference = c("2024-10", "2024-11"))
  v <- qc_surveillance_data(d, expect_latest = "2024-13")
  expect_false(v$ok)
  expect_match(v$reasons, "not updated")
})

test_that("min_rows is honoured", {
  d <- data.table::data.table(isoyearweek_reference = "2024-11")
  expect_false(qc_surveillance_data(d, min_rows = 2)$ok)
  expect_true(qc_surveillance_data(d, min_rows = 1)$ok)
})
