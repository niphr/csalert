# Backtest-driven recalibration: estimate a correction from past nowcasts vs
# truth, apply it, and confirm the intervals hit nominal coverage even when the
# engine itself is under-dispersed (drifting delay).

skip_if_not_installed("flexsurv")

gen_drift <- function(n_weeks = 80, max_delay = 5, seed = 5) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek; i0 <- which(weeks == "2020-01")
  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 60 * (1 + 0.5 * sin(2 * pi * w / 52))); if (n == 0) next
    dp <- ((max_delay:1) + (w / n_weeks) * 3 * (1:max_delay)); dp <- dp / sum(dp)
    del <- sample(0:(max_delay - 1), n, replace = TRUE, prob = dp)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = weeks[i0 + w - 1],
                                        rep_idx = (i0 + w - 1) + del)
  }
  ll <- data.table::rbindlist(rows); ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  csfmt_reporting_triangle_v3(tri[], id_cols = c("indicator", "location", "age", "sex"))
}

# central-interval coverage from long quantile predictions + truth
cov_at <- function(dt, truth, lo = 0.05, hi = 0.95) {
  d <- merge(data.table::as.data.table(dt), truth, by = "reference")
  qlevs <- sort(unique(d$quantile_level))
  loq <- qlevs[which.min(abs(qlevs - lo))]; hiq <- qlevs[which.min(abs(qlevs - hi))]
  lo_v <- d[quantile_level == loq, .(lo = predicted[1], truth = truth[1]), by = .(reference, horizon)]
  hi_v <- d[quantile_level == hiq, .(hi = predicted[1]), by = .(reference, horizon)]
  m <- merge(lo_v, hi_v, by = c("reference", "horizon"))
  mean(m$truth >= m$lo & m$truth <= m$hi)
}

test_that("estimate + apply calibration lifts drift coverage to nominal", {
  tri <- gen_drift()
  m <- function(x) nowcast_survrtrunc_v1(x, max_delay = 5, n_sim = 500, delay_window = 26)
  bt <- nowcast_backtest(tri, m, max_delay = 5, horizons = 1:2,
                         probs = c(.05, .25, .5, .75, .95), seed = 1)
  truth <- nowcast_truth(tri, 5)

  before <- cov_at(bt, truth)
  cal    <- nowcast_estimate_calibration_v1(bt, truth, level = 0.9)
  bt_cal <- nowcast_apply_calibration_v1(bt, cal)
  after  <- cov_at(bt_cal, truth)

  expect_s3_class(cal, "nowcast_calibration")
  expect_true(all(c("horizon", "n", "coverage_raw", "factor") %in% names(cal$table)))
  expect_true(all(cal$table$factor > 1))     # under-dispersed -> widen
  expect_lt(before, 0.82)                    # raw engine under-covers
  expect_gte(after, 0.85)                    # recalibrated ~ nominal (0.90)
})

test_that("apply passes through groups with no learned factor", {
  tri <- gen_drift()
  m <- function(x) nowcast_survrtrunc_v1(x, max_delay = 5, n_sim = 300, delay_window = 26)
  bt <- nowcast_backtest(tri, m, max_delay = 5, horizons = 1:2,
                         probs = c(.05, .5, .95), seed = 1)
  truth <- nowcast_truth(tri, 5)
  cal <- nowcast_estimate_calibration_v1(bt[horizon == 1], truth, level = 0.9)  # only h1 learned
  out <- nowcast_apply_calibration_v1(bt, cal)
  # horizon 2 (unseen) is unchanged
  h2 <- merge(bt[horizon == 2], out[horizon == 2],
              by = c("reference", "horizon", "quantile_level"), suffixes = c(".in", ".out"))
  expect_equal(h2$predicted.in, h2$predicted.out)
})
