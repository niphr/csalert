# Calibration: does a nowcast's X% interval actually cover the truth X% of the
# time? Measured by replaying the engine (nowcast_backtest) on a synthetic process
# with KNOWN truth and comparing empirical vs nominal interval coverage.
#
# Key lesson (and the reason the old coverage test missed it): a calibration test
# only bites if the generator contains the misspecification the engine is
# vulnerable to. nowcast_simple_v1 pools ALL history into one stationary delay
# estimate -- it is well-calibrated when the reporting delay is stationary, but
# UNDER-covers badly when the delay DRIFTS over time (which real reporting does:
# ~0.57 vs 0.90 nominal, matching the real-data backtest). Overdispersion in the
# counts, by contrast, does not hurt coverage. So we test both regimes.

skip_if_not_installed("flexsurv")

# Synthetic reporting triangle with a seasonal mean and a delay distribution that
# optionally DRIFTS toward longer delays over time.
gen_tri <- function(n_weeks = 70, max_delay = 5, seed = 3, drift = FALSE) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek; i0 <- which(weeks == "2020-01")
  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 60 * (1 + 0.5 * sin(2 * pi * w / 52)))
    if (n == 0) next
    dp <- if (drift) ((max_delay:1) + (w / n_weeks) * 3 * (1:max_delay)) else (max_delay:1)
    del <- sample(0:(max_delay - 1), n, replace = TRUE, prob = dp / sum(dp))
    rows[[w]] <- data.table::data.table(isoyearweek_reference = weeks[i0 + w - 1],
                                        rep_idx = (i0 + w - 1) + del)
  }
  ll <- data.table::rbindlist(rows)
  ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  csfmt_reporting_triangle_v3(tri[], id_cols = c("indicator", "location", "age", "sex"))
}

# Empirical interval coverage of nowcast_simple_v1, over a replay of the triangle.
interval_coverage <- function(tri, max_delay = 5) {
  m <- function(x) nowcast_simple_v1(x, max_delay = max_delay, n_sim = 500)
  bt <- nowcast_backtest(tri, m, max_delay = max_delay, horizons = 1:2,
                         probs = c(.05, .25, .5, .75, .95), seed = 1)
  d <- merge(bt, nowcast_truth(tri, max_delay), by = "reference")
  w <- data.table::dcast(d, reference + horizon + truth ~ quantile_level, value.var = "predicted")
  c(c90 = mean(w$truth >= w[["0.05"]] & w$truth <= w[["0.95"]]),
    c50 = mean(w$truth >= w[["0.25"]] & w$truth <= w[["0.75"]]))
}

test_that("nowcast_simple_v1 is well-calibrated when the delay is stationary", {
  cov <- interval_coverage(gen_tri(drift = FALSE))
  expect_gte(cov[["c90"]], 0.83)   # nominal 0.90
  expect_gte(cov[["c50"]], 0.40)   # nominal 0.50
})

test_that("nowcast_simple_v1 UNDER-covers when the delay drifts (known limitation)", {
  # A pooled, stationary delay estimate is stale for the recent weeks once the
  # delay drifts -> intervals too narrow. This characterises the CURRENT engine
  # (measured c90 ~ 0.57). A time-varying / Bayesian engine (a future
  # nowcast_*_v2 or stan) should push c90 >= 0.85 -- at which point flip this to
  # an expect_gte and it becomes the acceptance test.
  cov <- interval_coverage(gen_tri(drift = TRUE))
  expect_lt(cov[["c90"]], 0.75)
})
