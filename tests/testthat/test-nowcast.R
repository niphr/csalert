# passthrough nowcast: triangle -> ensemble (no completion). The modelling engine
# is covered by test-nowcast_delay_ecdf.R.
#
# The reporting axis is a DATE. Delays are drawn in whole weeks and then landed
# on the reporting Monday that many weeks after the reference Monday, so
# max_delay_weeks = 4 becomes max_delay_days = 28 and the delay cells sit on
# days 0, 7, 14 and 21.

# Simulate a KNOWN process: Poisson reference-week counts, each case reported with
# a delay drawn from a known decreasing distribution, then right-truncated at the
# latest week.
simulate_triangle <- function(
    n_weeks = 18, lambda = 60, max_delay_weeks = 4, seed = 1) {
  set.seed(seed)
  # 2019-12-30 is the Monday of ISO week 2020-01
  mondays <- as.Date("2019-12-30") + 7L * (seq_len(n_weeks) - 1L)
  ref_weeks <- format(mondays, "%G-%V")
  delay_p <- (max_delay_weeks:1) / sum(max_delay_weeks:1)

  rows <- list(); truth <- integer(n_weeks)
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, lambda); truth[w] <- n
    if (n == 0) next
    delays <- sample(0:(max_delay_weeks - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        reporting_date = mondays[w] + 7L * delays)
  }
  ll <- data.table::rbindlist(rows)
  ll <- ll[reporting_date <= mondays[n_weeks]]            # truncate at as-of
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, reporting_date)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  list(tri = tri[],
       truth = data.table::data.table(isoyearweek = ref_weeks, truth = truth))
}

test_that("passthrough surfaces the observed denominator total (role = observed)", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay_weeks = 4, seed = 3)
  sim$tri[, denominator := numerator * 3L + 1L]          # denominator > numerator
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"), value_col = "numerator")
  ens <- nowcast_passthrough_to_ensemble_v1(
    tri, max_delay_days = 28, denominator_col = "denominator")

  expect_true(all(c("numerator_nowcasted", "denominator_nowcasted") %in% names(ens$draws)))
  expect_true("denominator_observed" %in% names(ens$data))
  expect_true(all(ens$data$denominator_observed >= 0))
  expect_true(all(ens$data$denominator_observed >= ens$data$original))
})

test_that("passthrough passes the triangle through without nowcasting", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay_weeks = 4, seed = 5)
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"))
  ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay_days = 28)

  expect_s3_class(ens, "csfmt_ensemble_v3")
  # degenerate: a single draw column
  expect_equal(ncol(ens$draws$numerator_nowcasted), 1L)
  # the "nowcasted" value equals the observed total (no completion applied)
  expect_equal(as.numeric(ens$draws$numerator_nowcasted[, 1]), ens$data$original)

  # collapse -> every quantile equals the observed point
  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  expect_equal(out$numerator_nowcasted_q50x0, out$original)
  expect_equal(out$numerator_nowcasted_q02x5, out$original)
  expect_equal(out$numerator_nowcasted_q97x5, out$original)
})
