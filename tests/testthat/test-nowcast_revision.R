# nowcast_revision: recover a known revision pattern from a synthetic backtest.

test_that("nowcast_revision summarises signed/abs revision + tail probabilities by horizon", {
  # two horizons: h=0 medians are ~20% below truth with spread; h=1 nearly exact.
  set.seed(1)
  refs <- sprintf("2025-%02d", 1:40)
  truth <- data.table::data.table(reference = refs, truth = rep(100, 40))
  mk <- function(h, mult) data.table::data.table(
    reference = refs, as_of = refs, horizon = h, quantile_level = 0.5,
    predicted = 100 * mult)
  bt <- data.table::rbindlist(list(
    mk(0L, 0.80 + stats::runif(40, -0.15, 0.15)),   # h0: centred ~-20%, wide
    mk(1L, 1.00 + stats::runif(40, -0.02, 0.02))))  # h1: centred ~0, tight

  r <- nowcast_revision(bt, truth, by = "horizon")
  expect_true(all(c("n", "median_signed", "median_abs", "q05", "q95",
                    "p_gt_25", "p_gt_50") %in% names(r)))
  r0 <- r[horizon == 0]; r1 <- r[horizon == 1]
  expect_equal(r0$n, 40L)
  expect_lt(r0$median_signed, -0.1)          # h0 systematically below truth (bias)
  expect_lt(abs(r1$median_signed), 0.03)     # h1 ~unbiased
  expect_gt(r0$median_abs, r1$median_abs)    # h0 revises more than h1
  expect_lt(r0$q05, r0$q95)                   # a real band
  expect_lt(r1$q95, 0.05)                     # h1 band is tight
  expect_gte(r0$p_gt_25, 0)                    # tail prob in [0,1]
  expect_lte(r0$p_gt_25, 1)
})

test_that("nowcast_revision ignores settled truth of zero and errors on empty", {
  refs <- c("2025-01", "2025-02", "2025-03")
  truth <- data.table::data.table(reference = refs, truth = c(0, 50, 50))
  bt <- data.table::data.table(reference = refs, as_of = refs, horizon = 0L,
    quantile_level = 0.5, predicted = c(10, 55, 45))
  r <- nowcast_revision(bt, truth)
  expect_equal(r$n, 2L)                        # the truth==0 week dropped
  expect_error(nowcast_revision(bt[0], truth), "empty backtest")
})
