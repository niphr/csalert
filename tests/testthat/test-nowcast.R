# passthrough nowcast: triangle -> ensemble (no completion). The modelling engine
# is covered by test-nowcast_quasipoisson.R.

# Simulate a KNOWN process: Poisson reference-week counts, each case reported with
# a delay drawn from a known decreasing distribution, then right-truncated at the
# latest week.
simulate_triangle <- function(n_weeks = 18, lambda = 60, max_delay = 4, seed = 1) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2020-01")
  ref_weeks <- weeks[i0:(i0 + n_weeks - 1)]
  delay_p <- (max_delay:1) / sum(max_delay:1)

  rows <- list(); truth <- integer(n_weeks)
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, lambda); truth[w] <- n
    if (n == 0) next
    delays <- sample(0:(max_delay - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        rep_idx = (i0 + w - 1) + delays)
  }
  ll <- data.table::rbindlist(rows)
  ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]                  # truncate at as-of
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  list(tri = tri[],
       truth = data.table::data.table(isoyearweek = ref_weeks, truth = truth))
}

test_that("passthrough surfaces the observed denominator total (role = observed)", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay = 4, seed = 3)
  sim$tri[, denominator := numerator * 3L + 1L]          # denominator > numerator
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"), value_col = "numerator")
  ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay = 4, denominator_col = "denominator")

  expect_true(all(c("numerator_nowcasted", "denominator_nowcasted") %in% names(ens$draws)))
  expect_true("denominator_observed" %in% names(ens$data))
  expect_true(all(ens$data$denominator_observed >= 0))
  expect_true(all(ens$data$denominator_observed >= ens$data$original))
})

test_that("passthrough passes the triangle through without nowcasting", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay = 4, seed = 5)
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"))
  ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay = 4)

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
