# .evaluate_backtest (the scorer behind nowcast_evaluate_v1): recover known
# coverage + revision from a synthetic backtest (quantile nowcasts with a
# controlled median bias and interval width).
#
# `as_of` is a Date here, and it is a merge key inside the scorer. These tests
# pin that it stays a Date through the merges and through the group-by.

# 40 reference weeks, and the Monday that starts each one
mk_refs <- function(nref = 40L) {
  mondays <- as.Date("2024-12-30") + 7L * (seq_len(nref) - 1L)
  list(mondays = mondays, refs = format(mondays, "%G-%V"), nref = nref)
}

# one backtest block per horizon: 5 quantiles (0.05/0.25/0.5/0.75/0.95) per ref,
# centred at `med` with half-width `half`.
mk_block <- function(r, h, med, half) {
  data.table::data.table(
    reference = rep(r$refs, each = 5),
    as_of = rep(r$mondays, each = 5),
    horizon = h,
    quantile_level = rep(c(0.05, 0.25, 0.5, 0.75, 0.95), r$nref),
    predicted = as.numeric(rbind(
      med - half,
      med - half / 2,
      med,
      med + half / 2,
      med + half
    ))
  )
}

test_that(".evaluate_backtest summarises coverage + revision by horizon", {
  set.seed(1)
  r <- mk_refs()
  truth <- data.table::data.table(reference = r$refs, truth = 100)

  med0 <- 80 + stats::runif(r$nref, -5, 5) # h0: ~20% below truth, wide
  med1 <- 100 + stats::runif(r$nref, -1, 1) # h1: ~unbiased, tight
  bt <- data.table::rbindlist(list(
    mk_block(r, 0L, med0, 25),
    mk_block(r, 1L, med1, 4)
  ))

  ev <- .evaluate_backtest(bt, truth, by = "horizon")
  expect_true(all(
    c(
      "n",
      "coverage_50",
      "coverage_90",
      "median_signed",
      "median_abs",
      "q05",
      "q95",
      "p_gt_25",
      "p_gt_50"
    ) %in%
      names(ev)
  ))
  e0 <- ev[horizon == 0]
  e1 <- ev[horizon == 1]
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

test_that(".evaluate_backtest carries a Date as_of through the merge and group-by", {
  set.seed(2)
  r <- mk_refs()
  truth <- data.table::data.table(reference = r$refs, truth = 100)
  bt <- data.table::rbindlist(list(
    mk_block(r, 0L, 90 + stats::runif(r$nref, -5, 5), 20),
    mk_block(r, 1L, 100 + stats::runif(r$nref, -2, 2), 8)
  ))
  expect_s3_class(bt$as_of, "Date")

  # `as_of` is one of the three merge keys, so a Date has to survive four merges
  by_h <- .evaluate_backtest(bt, truth, by = "horizon")
  expect_equal(nrow(by_h), 2L)
  expect_equal(sum(by_h$n), 80L)

  # and it has to survive being the group-by column itself
  by_a <- .evaluate_backtest(bt, truth, by = "as_of")
  expect_s3_class(by_a$as_of, "Date")
  expect_setequal(by_a$as_of, r$mondays)
  expect_true(all(by_a$n == 2L)) # two horizons per as-of date
})

test_that(".evaluate_backtest errors on an empty backtest", {
  truth <- data.table::data.table(reference = character(0), truth = numeric(0))
  expect_error(
    .evaluate_backtest(data.table::data.table(), truth),
    "empty backtest"
  )
})
