# End-to-end: triangle -> nowcast -> short_term_trend -> collapse.

skip_if_not_installed("flexsurv")

test_that("the full draw-parallel pipeline composes via the pipe", {
  set.seed(1)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2020-01"); n_weeks <- 20; max_delay <- 4
  ref_weeks <- weeks[i0:(i0 + n_weeks - 1)]
  delay_p <- (max_delay:1) / sum(max_delay:1)

  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 50)
    delays <- sample(0:(max_delay - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        rep_idx = (i0 + w - 1) + delays)
  }
  ll <- data.table::rbindlist(rows)
  ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri_dt <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri_dt[, `:=`(indicator = "flu", location = "nation", age = "total", sex = "total")]

  out <- csfmt_reporting_triangle_v3(tri_dt, id_cols = c("indicator", "location", "age", "sex")) |>
    nowcast_simple_v1(max_delay = 4, n_sim = 200) |>
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
