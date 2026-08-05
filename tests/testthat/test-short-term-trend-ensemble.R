
# short_term_trend() used to add its P(increasing) column with base `[[<-`, which
# copies the data.table and breaks its self-reference. The NEXT ensemble stage to
# use `:=` on $data then emitted data.table's "shallow copy was taken" advisory.
# It fired in the canonical order rate -> trend -> mem -> hlm, so every production
# pipeline running a trend before another stage saw it.
test_that("short_term_trend leaves $data usable by a later := stage", {
  set.seed(1)
  w <- cstime::dates_by_isoyearweek$isoyearweek
  i <- match("2023-01", w)
  n <- 60
  d <- data.table::data.table(
    isoyearweek_reference = w[i + rep(0:(n - 1), each = 3)],
    isoyearweek_reporting = w[i + rep(0:(n - 1), each = 3) + rep(0:2, n)],
    numerator = stats::rpois(3 * n, c(40, 20, 8)),
    denominator = stats::rpois(3 * n, c(400, 200, 80)),
    indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
  )
  d <- d[isoyearweek_reporting <= w[i + n - 1]]
  tri <- csfmt_reporting_triangle_v3(
    d, id_cols = c("indicator_tag", "location_code", "age", "sex")
  )
  ens <- nowcast_quasipoisson_v1(
    tri, max_delay = 3, n_sim = 60, denominator_col = "denominator"
  )
  ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)

  # the next stage assigns with `:=`; it must not warn about a shallow copy
  expect_no_warning(signal_detection_hlm(ens, measure = "numerator_nowcasted"))
})
