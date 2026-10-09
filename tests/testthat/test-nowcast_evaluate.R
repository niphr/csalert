# .evaluate_backtest (the scorer behind nowcast_score_v1): recover known
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

# One forecast unit with seven quantiles, so three central intervals (K = 3).
mk_unit <- function(y) {
  list(
    truth = data.table::data.table(reference = "2024-01", truth = y),
    bt = data.table::data.table(
      reference = "2024-01",
      horizon = 0L,
      quantile_level = c(0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975),
      predicted = c(60, 70, 85, 95, 105, 120, 130)
    )
  )
}

test_that("nowcast_score_v1 matches a hand-computed WIS and wis_log for one unit", {
  u <- mk_unit(110)
  s <- nowcast_score_v1(u$bt, u$truth)
  # truth 110, median 95; the 50% interval [85, 105] misses the truth by 5.
  # 95%: alpha 0.05, IS = 130 - 60 = 70, weight 0.025
  # 90%: alpha 0.10, IS = 120 - 70 = 50, weight 0.05
  # 50%: alpha 0.50, IS = 105 - 85 + (2 / 0.5) * (110 - 105) = 40, weight 0.25
  expect_equal(
    s$wis,
    (0.5 * 15 + 0.025 * 70 + 0.05 * 50 + 0.25 * 40) / 3.5,
    tolerance = 1e-12
  )
  expect_equal(s$wis, 21.75 / 3.5, tolerance = 1e-12)
  # the same on log1p() of every quantile and of the truth
  is95 <- log1p(130) - log1p(60)
  is90 <- log1p(120) - log1p(70)
  is50 <- log1p(105) - log1p(85) + 4 * (log1p(110) - log1p(105))
  expect_equal(
    s$wis_log,
    (0.5 *
      (log1p(110) - log1p(95)) +
      0.025 * is95 +
      0.05 * is90 +
      0.25 * is50) /
      3.5,
    tolerance = 1e-12
  )
})

test_that("nowcast_score_v1 agrees with scoringutils on wis and wis_log", {
  skip_if_not_installed("scoringutils")
  set.seed(4)
  lv <- c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975)
  refs <- sprintf("2024-%02d", 1:30)
  bt <- data.table::rbindlist(lapply(0:1, function(h) {
    mu <- stats::rnorm(30, 100, 15)
    data.table::data.table(
      reference = rep(refs, each = 9),
      horizon = h,
      quantile_level = rep(lv, 30),
      predicted = as.numeric(sapply(mu, function(m) m + 20 * stats::qnorm(lv)))
    )
  }))
  truth <- data.table::data.table(
    reference = refs,
    truth = stats::rpois(30, 100)
  )
  s <- nowcast_score_v1(bt, truth)

  su_wis <- function(d) {
    fc <- scoringutils::as_forecast_quantile(
      d,
      observed = "truth",
      forecast_unit = c("reference", "horizon")
    )
    sc <- scoringutils::score(fc, metrics = list(wis = scoringutils::wis))
    return(sc[, list(wis = mean(wis)), by = "horizon"])
  }
  d <- merge(bt, truth, by = "reference")
  ref <- su_wis(d)
  expect_equal(s$wis, ref$wis[match(s$horizon, ref$horizon)], tolerance = 1e-8)

  dl <- data.table::copy(d)[, `:=`(
    predicted = log1p(predicted),
    truth = log1p(truth)
  )]
  ref_log <- su_wis(dl)
  expect_equal(
    s$wis_log,
    ref_log$wis[match(s$horizon, ref_log$horizon)],
    tolerance = 1e-8
  )
})

test_that("nowcast_score_v1 reports coverage_95 and width_95_rel_median", {
  # two units at horizon 0: truth 100 inside [60, 130], truth 140 outside it
  truth <- data.table::data.table(
    reference = c("2024-01", "2024-02"),
    truth = c(100, 140)
  )
  bt <- data.table::rbindlist(list(
    mk_unit(100)$bt,
    mk_unit(140)$bt[, reference := "2024-02"]
  ))
  s <- nowcast_score_v1(bt, truth)
  expect_equal(s$coverage_95, 0.5)
  # widths 70 / 100 = 0.7 and 70 / 140 = 0.5, median 0.6
  expect_equal(s$width_95_rel_median, 0.6)

  # a truth of 0 divides by 1: the width is 70
  z <- mk_unit(0)
  expect_equal(nowcast_score_v1(z$bt, z$truth)$width_95_rel_median, 70)

  # no 0.025 and 0.975 quantiles: NA, not an error
  u <- mk_unit(100)
  s5 <- nowcast_score_v1(u$bt[!quantile_level %in% c(0.025, 0.975)], u$truth)
  expect_true(is.na(s5$coverage_95))
  expect_true(is.na(s5$width_95_rel_median))
  expect_false(is.na(s5$wis))
})

test_that("nowcast_score_v1 keeps the .evaluate_backtest columns on the existing fixtures", {
  old_cols <- c(
    "n",
    "coverage_50",
    "coverage_90",
    "median_signed",
    "median_abs",
    "q05",
    "q95",
    "p_gt_25",
    "p_gt_50"
  )
  # the backtest of the first .evaluate_backtest test
  set.seed(1)
  r <- mk_refs()
  truth <- data.table::data.table(reference = r$refs, truth = 100)
  bt1 <- data.table::rbindlist(list(
    mk_block(r, 0L, 80 + stats::runif(r$nref, -5, 5), 25),
    mk_block(r, 1L, 100 + stats::runif(r$nref, -1, 1), 4)
  ))
  # the backtest of the second, Date as_of, test
  set.seed(2)
  bt2 <- data.table::rbindlist(list(
    mk_block(r, 0L, 90 + stats::runif(r$nref, -5, 5), 20),
    mk_block(r, 1L, 100 + stats::runif(r$nref, -2, 2), 8)
  ))
  for (case in list(
    list(bt1, "horizon"),
    list(bt2, "horizon"),
    list(bt2, "as_of")
  )) {
    by <- case[[2]]
    s <- nowcast_score_v1(case[[1]], truth, by = by)
    e <- .evaluate_backtest(case[[1]], truth, by = by)
    expect_equal(
      s[, c(by, old_cols), with = FALSE],
      e[, c(by, old_cols), with = FALSE]
    )
  }
})

test_that("nowcast_score_v1 is exported", {
  expect_true("nowcast_score_v1" %in% getNamespaceExports("csalert"))
})

# The fixed values below were pinned through nowcast_evaluate_v1 (removed in
# 2026.10.12). That function ran nowcast_backtest() and then nowcast_score_v1(),
# so the same two calls MUST give the same values.
mk_tri <- function() {
  set.seed(11)
  mondays <- as.Date("2019-12-30") + 7L * 0:19
  d <- data.table::rbindlist(lapply(seq_along(mondays), function(w) {
    data.table::data.table(
      isoyearweek_reference = format(mondays[w], "%G-%V"),
      reporting_date = mondays[w] + 7L * 0:3,
      numerator = stats::rpois(4, c(40, 25, 10, 5))
    )
  }))
  d <- d[reporting_date <= max(mondays)]
  d[, `:=`(indicator = "x", location = "n", age = "total", sex = "total")]
  return(csfmt_reporting_triangle_v3(
    d,
    id_cols = c("indicator", "location", "age", "sex")
  ))
}

test_that("nowcast_backtest + nowcast_score_v1 keep the 9120b29 values", {
  tri <- mk_tri()
  bt <- nowcast_backtest(
    tri,
    function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 28, n_sim = 100),
    max_delay_days = 28,
    horizons = 0:2,
    probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
    seed = 3
  )
  ev <- nowcast_score_v1(bt, nowcast_truth(tri, 28))
  old <- list(
    horizon = 2:0,
    n = 14:12,
    coverage_50 = c(0.214, 0.308, 0.583),
    coverage_90 = c(0.5, 0.538, 0.833),
    median_signed = c(-0.015, -0.0213, -0.027),
    median_abs = c(0.0237, 0.0355, 0.0748),
    q05 = c(-0.0535, -0.1426, -0.4423),
    q95 = c(0.0244, 0.0609, 0.1506),
    p_gt_25 = c(0, 0, 0.1667),
    p_gt_50 = c(0, 0, 0)
  )
  expect_equal(as.list(ev[, names(old), with = FALSE]), old)
})
