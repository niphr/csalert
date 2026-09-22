# End-to-end: triangle -> nowcast -> short_term_trend -> collapse.
#
# The reporting axis is a DATE. Delays are drawn in whole weeks and then landed
# on the reporting Monday that many weeks after the reference Monday, so
# max_delay_weeks = 4 becomes max_delay_days = 28.

test_that("the full draw-parallel pipeline composes via the pipe", {
  set.seed(1)
  n_weeks <- 20; max_delay_weeks <- 4
  # 2019-12-30 is the Monday of ISO week 2020-01
  mondays <- as.Date("2019-12-30") + 7L * (seq_len(n_weeks) - 1L)
  ref_weeks <- format(mondays, "%G-%V")
  delay_p <- (max_delay_weeks:1) / sum(max_delay_weeks:1)

  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 50)
    delays <- sample(0:(max_delay_weeks - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        reporting_date = mondays[w] + 7L * delays)
  }
  ll <- data.table::rbindlist(rows)
  ll <- ll[reporting_date <= mondays[n_weeks]]
  tri_dt <- ll[, .(numerator = .N), by = .(isoyearweek_reference, reporting_date)]
  tri_dt[, `:=`(indicator = "flu", location = "nation", age = "total", sex = "total")]

  out <- csfmt_reporting_triangle_v3(tri_dt, id_cols = c("indicator", "location", "age", "sex")) |>
    nowcast_delay_ecdf_v1(max_delay_days = 28, n_sim = 200) |>
    short_term_trend(measure = "numerator_nowcasted", trend_isoyearweeks = 3) |>
    ens_collapse(probs = c(0.025, 0.5, 0.975))

  expect_s3_class(out, "data.table")
  expect_equal(nrow(out), n_weeks)
  # nowcast quantiles AND growth-rate quantiles, all grammar-named
  expect_true(all(c("numerator_nowcasted_q02x5",
                    "numerator_nowcasted_q50x0",
                    "numerator_nowcasted_q97x5",
                    "numerator_nowcasted_trend_gr_q50x0") %in% names(out)))
  # growth rate defined past the leading trend window, NA before it
  gr <- out$numerator_nowcasted_trend_gr_q50x0
  expect_true(all(is.na(gr[1:2])))
  expect_true(any(is.finite(gr[3:n_weeks])))
})
