# nowcast_evaluate_v1: recover known coverage + revision from a synthetic backtest
# (quantile nowcasts with a controlled median bias and interval width).

test_that("nowcast_evaluate_v1 summarises coverage + revision by horizon", {
  set.seed(1)
  refs <- sprintf("2025-%02d", 1:40); nref <- 40L
  truth <- data.table::data.table(reference = refs, truth = 100)

  # one backtest block per horizon: 5 quantiles (0.05/0.25/0.5/0.75/0.95) per ref,
  # centred at `med` with half-width `half`.
  mk <- function(h, med, half) data.table::data.table(
    reference = rep(refs, each = 5), as_of = rep(refs, each = 5), horizon = h,
    quantile_level = rep(c(0.05, 0.25, 0.5, 0.75, 0.95), nref),
    predicted = as.numeric(rbind(med - half, med - half / 2, med, med + half / 2, med + half)))

  med0 <- 80 + stats::runif(nref, -5, 5)      # h0: ~20% below truth, wide
  med1 <- 100 + stats::runif(nref, -1, 1)     # h1: ~unbiased, tight
  bt <- data.table::rbindlist(list(mk(0L, med0, 25), mk(1L, med1, 4)))

  ev <- nowcast_evaluate_v1(bt, truth, by = "horizon")
  expect_true(all(c("n", "coverage_50", "coverage_90", "median_signed", "median_abs",
                    "q05", "q95", "p_gt_25", "p_gt_50") %in% names(ev)))
  e0 <- ev[horizon == 0]; e1 <- ev[horizon == 1]
  expect_equal(e0$n, 40L)
  # revision: h0 systematically below truth, h1 ~unbiased and revises less
  expect_lt(e0$median_signed, -0.1)
  expect_lt(abs(e1$median_signed), 0.03)
  expect_gt(e0$median_abs, e1$median_abs)
  # coverage: both 90% intervals contain the truth for (nearly) every week
  expect_gt(e0$coverage_90, 0.8)
  expect_gt(e1$coverage_90, 0.8)
  expect_true(all(ev$coverage_50 >= 0 & ev$coverage_50 <= 1))
})

test_that("nowcast_evaluate_v1 errors on an empty backtest", {
  truth <- data.table::data.table(reference = character(0), truth = numeric(0))
  expect_error(nowcast_evaluate_v1(data.table::data.table(), truth), "empty backtest")
})
