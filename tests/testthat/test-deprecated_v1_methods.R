# The ensemble is the analysis substrate and ens_collapse() is terminal, so a
# collapsed csfmt_rts_data_v3 is output and never input. These tests pin the two
# halves of that contract:
#   1. the v3 methods exist only to say so, and always stop() with a signpost;
#   2. the csfmt_rts_data_v1 table methods run SILENTLY. They are supported for
#      counts without delayed reporting, and norsyss.cs9 calls both nightly, so
#      a runtime warning would only fill its logs.

test_that("short_term_trend() on a csfmt_rts_data_v3 stops with a signpost", {
  d <- data.table::data.table(
    location_code = "nation",
    age = "total",
    sex = "total",
    border = 2020,
    isoyearweek = c("2023-01", "2023-02", "2023-03"),
    numerator_nowcasted_q50x0 = c(10, 12, 14)
  )
  cstidy::set_csfmt_rts_data_v3(d)
  expect_s3_class(d, "csfmt_rts_data_v3")

  expect_error(short_term_trend(d), "does not accept a csfmt_rts_data_v3")
  expect_error(short_term_trend(d), "BEFORE ens_collapse")
})

test_that("signal_detection_hlm() on a csfmt_rts_data_v3 stops with a signpost", {
  d <- data.table::data.table(
    location_code = "nation",
    age = "total",
    sex = "total",
    border = 2020,
    isoyearweek = c("2023-01", "2023-02", "2023-03"),
    numerator_nowcasted_q50x0 = c(10, 12, 14)
  )
  cstidy::set_csfmt_rts_data_v3(d)
  expect_s3_class(d, "csfmt_rts_data_v3")

  expect_error(signal_detection_hlm(d), "does not accept a csfmt_rts_data_v3")
  expect_error(signal_detection_hlm(d), "BEFORE ens_collapse")
})

test_that("the csfmt_rts_data_v1 table methods emit no runtime condition", {
  d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
  d <- d[granularity_time == "isoyearweek"]

  # a supported method: no warning, no message, no condition at all
  expect_no_warning(
    res_trend <- short_term_trend(
      d,
      numerator = "hospitalization_with_covid19_as_primary_cause_n",
      trend_isoyearweeks = 6
    )
  )
  expect_s3_class(res_trend, "csfmt_rts_data_v1")

  expect_no_warning(
    res_hlm <- signal_detection_hlm(
      d,
      value = "hospitalization_with_covid19_as_primary_cause_n",
      baseline_isoyears = 1
    )
  )
  expect_s3_class(res_hlm, "csfmt_rts_data_v1")
})
