
# short_term_trend() used to add its P(increasing) column with base `[[<-`, which
# copies the data.table and breaks its self-reference. The NEXT ensemble stage to
# use `:=` on $data then emitted data.table's "shallow copy was taken" advisory.
# It fired in the canonical order rate -> trend -> mem -> hlm, so every production
# pipeline running a trend before another stage saw it.
test_that("short_term_trend leaves $data usable by a later := stage", {
  set.seed(1)
  n <- 60
  # 2023-01-02 is the Monday of ISO week 2023-01. Each reference week reports
  # on delay days 0, 7 and 14, so max_delay_days = 21 holds three delay cells.
  mondays <- as.Date("2023-01-02") + 7 * (0:(n - 1))
  monday <- rep(mondays, each = 3)
  d <- data.table::data.table(
    isoyearweek_reference = format(monday, "%G-%V"),
    reporting_date = monday + rep(c(0, 7, 14), n),
    numerator = stats::rpois(3 * n, c(40, 20, 8)),
    denominator = stats::rpois(3 * n, c(400, 200, 80)),
    indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
  )
  d <- d[reporting_date <= mondays[n] + 6]
  tri <- csfmt_reporting_triangle_v3(
    d, id_cols = c("indicator_tag", "location_code", "age", "sex")
  )
  ens <- nowcast_delay_ecdf_v1(
    tri, max_delay_days = 21, n_sim = 60, denominator_col = "denominator"
  )
  ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)

  # the next stage assigns with `:=`; it must not warn about a shallow copy
  expect_no_warning(signal_detection_hlm(ens, measure = "numerator_nowcasted"))
})
