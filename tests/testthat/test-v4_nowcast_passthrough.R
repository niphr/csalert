# nowcast_passthrough_v4 is a copy of nowcast_passthrough_to_ensemble_v1. Its
# draws MUST be identical() to those of v3.

v4_pass_raw <- function() {
  set.seed(2)
  cal <- cstime::dates_by_isoyearweek
  i <- match("2023-01", cal$isoyearweek)
  w <- rep(0:29, each = 3)
  raw <- data.table::rbindlist(lapply(c("nation", "county03"), function(loc) {
    return(data.table::data.table(
      isoyearweek_reference = cal$isoyearweek[i + w],
      reporting_date = as.Date(cal$mon[i + w]) + rep(c(3, 10, 40), 30),
      numerator = stats::rpois(90, c(30, 15, 5)),
      denominator = stats::rpois(90, c(300, 150, 50)),
      location_code = loc,
      age = "total"
    ))
  }))
  return(raw[raw$reporting_date <= as.Date(cal$mon[i + 29]) + 6])
}

test_that("nowcast_passthrough_v4 gives draws identical to v3", {
  raw <- v4_pass_raw()
  id <- c("location_code", "age")
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = id)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = id)
  e3 <- nowcast_passthrough_to_ensemble_v1(
    tri3,
    max_delay_days = 21,
    denominator_col = "denominator"
  )
  e4 <- nowcast_passthrough_v4(
    tri4,
    max_delay_days = 21,
    denominator_col = "denominator"
  )
  expect_identical(e4$draws$numerator, e3$draws$numerator_nowcasted)
  expect_identical(e4$draws$denominator, e3$draws$denominator_nowcasted)
  expect_identical(e4$data, e3$data)
  expect_s3_class(e4, "csfmt_ensemble_v4")
  expect_identical(e4$state, "full")
  expect_identical(e4$id_cols, id)
  expect_identical(e4$time_col, "isoyearweek")
  # the late report at delay day 40 is in the total
  expect_identical(e4$draws$numerator[, 1], e4$data$original)
})

test_that("nowcast_passthrough_v4 draws no random numbers", {
  tri4 <- csfmt_reporting_triangle_v4(
    v4_pass_raw(),
    id_cols = c("location_code", "age")
  )
  set.seed(8)
  before <- get(".Random.seed", envir = globalenv())
  nowcast_passthrough_v4(tri4, max_delay_days = 21)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that("nowcast_passthrough_v4 rejects a reserved suffix", {
  tri4 <- csfmt_reporting_triangle_v4(
    v4_pass_raw(),
    id_cols = c("location_code", "age")
  )
  expect_error(
    nowcast_passthrough_v4(
      tri4,
      max_delay_days = 21,
      denominator_col = "denominator_hlm"
    ),
    "reserved suffix"
  )
})
