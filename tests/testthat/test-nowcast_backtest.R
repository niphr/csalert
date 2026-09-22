# nowcast backtest/evaluate/compare harness, on a simulated triangle with held-out
# truth. Coverage + revision come straight from the interval quantiles (no external
# scoring package).
#
# The reporting axis is a DATE. Delays are drawn in whole weeks and then landed on
# the reporting Monday that many weeks after the reference Monday, so
# max_delay_weeks = 4 becomes max_delay_days = 28 and the delay cells sit on days
# 0, 7, 14 and 21.

# Simulate a KNOWN process: Poisson reference-week counts reported with a known
# decreasing delay, right-truncated at the latest week. Hold out the true totals.
sim_backtest_triangle <- function(
  n_weeks = 24,
  lambda = 80,
  max_delay_weeks = 4,
  seed = 7
) {
  set.seed(seed)
  # 2019-12-30 is the Monday of ISO week 2020-01
  mondays <- as.Date("2019-12-30") + 7L * (seq_len(n_weeks) - 1L)
  ref_weeks <- format(mondays, "%G-%V")
  delay_p <- (max_delay_weeks:1) / sum(max_delay_weeks:1)
  rows <- list()
  truth <- integer(n_weeks)
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, lambda)
    truth[w] <- n
    if (n == 0) {
      next
    }
    delays <- sample(0:(max_delay_weeks - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(
      isoyearweek_reference = ref_weeks[w],
      reporting_date = mondays[w] + 7L * delays
    )
  }
  ll <- data.table::rbindlist(rows)
  ll <- ll[reporting_date <= mondays[n_weeks]]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, reporting_date)]
  tri[, `:=`(
    indicator = "test",
    location = "nation",
    age = "total",
    sex = "total"
  )]
  list(
    tri = csfmt_reporting_triangle_v3(
      tri[],
      id_cols = c("indicator", "location", "age", "sex")
    ),
    truth = data.table::data.table(reference = ref_weeks, truth = truth),
    mondays = mondays,
    n_weeks = n_weeks,
    max_delay_days = 7L * max_delay_weeks
  )
}

test_that("nowcast_censor keeps only what was known as-of, and moves the boundary", {
  s <- sim_backtest_triangle()
  as_of <- s$mondays[11]
  expect_s3_class(as_of, "Date")
  cens <- nowcast_censor(s$tri, as_of)
  rep_col <- attr(cens, "reporting_col")
  expect_true(all(cens[[rep_col]] <= as_of))
  expect_equal(attr(cens, "as_of"), max(cens[[rep_col]]))
  expect_true(attr(cens, "as_of") <= as_of) # Date <= Date, a real date comparison
  # censoring to the full as-of is a no-op on the cell set
  expect_equal(nrow(nowcast_censor(s$tri, attr(s$tri, "as_of"))), nrow(s$tri))
})

test_that("nowcast_censor errors on an as_of that is not a Date", {
  s <- sim_backtest_triangle()
  # Measured on the pre-assertion tree, 2026-09-22. R read
  # `reporting date <= as_of` from the type of as_of, and each wrong type failed
  # differently. 18262 is a day count since 1970-01-01, so it censored to
  # 2020-01-01 and reported nothing wrong. "2020-11" went through as.Date() and
  # errored inside charToDate(), with a message that never named as_of. An IDate
  # gave the right answer. A factor raised an "Incompatible methods" warning and
  # then an unrelated error. One strict check at the boundary replaces all four.
  expect_error(nowcast_censor(s$tri, "2020-11"), "must be a Date")
  expect_error(nowcast_censor(s$tri, 18262), "must be a Date")
  expect_error(
    nowcast_censor(s$tri, data.table::as.IDate(s$mondays[11])),
    "must be a Date"
  )
  expect_error(nowcast_censor(s$tri, factor("2020-03-02")), "must be a Date")
})

test_that("nowcast_truth recovers the settled totals for old-enough weeks", {
  s <- sim_backtest_triangle()
  tr <- nowcast_truth(s$tri, max_delay_days = s$max_delay_days)
  # only settled weeks are returned: their Monday is at least max_delay_days - 1
  # days before the as-of date
  expect_true(nrow(tr) < s$n_weeks)
  # and their totals equal the held-out truth (all cases land within max_delay_days)
  chk <- merge(tr, s$truth, by = "reference", suffixes = c("_got", "_true"))
  expect_equal(chk$truth_got, chk$truth_true)
})

test_that("nowcast_backtest replays a method into a tidy long table", {
  s <- sim_backtest_triangle()
  passthrough <- function(x) {
    nowcast_passthrough_to_ensemble_v1(x, max_delay_days = s$max_delay_days)
  }
  bt <- nowcast_backtest(
    s$tri,
    passthrough,
    max_delay_days = s$max_delay_days,
    horizons = 1:2
  )

  expect_true(all(
    c("reference", "as_of", "horizon", "quantile_level", "predicted") %in%
      names(bt)
  ))
  # the default as-of set is dates, and `for (x in dates)` would have stripped
  # the class on the way through the replay loop
  expect_s3_class(bt$as_of, "Date")
  expect_setequal(unique(bt$horizon), 1:2)
  # passthrough is a point mass -> every quantile equals the observed-so-far
  by_fc <- bt[, .(spread = diff(range(predicted))), by = .(reference, horizon)]
  expect_true(all(by_fc$spread == 0))
})

test_that("nowcast_backtest builds its default as-of set from dates", {
  s <- sim_backtest_triangle()
  passthrough <- function(x) {
    nowcast_passthrough_to_ensemble_v1(x, max_delay_days = s$max_delay_days)
  }
  bt <- nowcast_backtest(
    s$tri,
    passthrough,
    max_delay_days = s$max_delay_days,
    horizons = 1:2
  )
  # every default as-of is the Sunday that ends a reference week, never an
  # ISO-week string
  expect_s3_class(bt$as_of, "Date")
  expect_true(all(unique(bt$as_of) %in% (s$mondays + 6L)))
  # burn-in: max_delay_days rounded up to whole weeks is dropped from the front
  burn_in <- ceiling(s$max_delay_days / 7)
  expect_equal(min(unique(bt$as_of)), s$mondays[burn_in + 1L] + 6L)
  # a non-Date as_of_weeks errors rather than replaying nothing
  expect_error(
    nowcast_backtest(
      s$tri,
      passthrough,
      as_of_weeks = format(s$mondays[10:12], "%G-%V"),
      max_delay_days = s$max_delay_days
    ),
    "must be a Date vector"
  )
})

# A method that CONSUMES the RNG. The seed test below needs one, and the package
# engine is not it. nowcast_delay_ecdf_v1 permutes its draws, but a quantile
# does not see that order, so its replayed quantiles do not move with the RNG.
# Measured 2026-09-22: two replays of this fixture under different RNG states
# returned identical `predicted` values over 36 rows, maximum absolute
# difference 0. A seed test driven by that engine passes whatever the seed does.
rng_method <- function(x, max_delay_days) {
  base <- nowcast_passthrough_to_ensemble_v1(x, max_delay_days = max_delay_days)
  d <- data.table::copy(base$data)
  n <- nrow(d)
  dr <- list()
  dr[[names(base$draws)[1]]] <- matrix(
    stats::rpois(n * 40L, rep(pmax(d$original, 1), 40L)),
    nrow = n
  )
  csfmt_ensemble_v3(
    d,
    id_cols = attr(x, "id_cols"),
    time_col = "isoyearweek",
    draws = dr
  )
}

test_that("nowcast_backtest seeds each as-of from the date, reproducibly", {
  s <- sim_backtest_triangle()
  m <- function(x) rng_method(x, s$max_delay_days)
  as_of <- s$mondays[c(14, 18, 22)] + 6L
  probs <- c(0.05, 0.5, 0.95)
  a <- nowcast_backtest(
    s$tri,
    m,
    as_of_weeks = as_of,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    probs = probs,
    seed = 11
  )
  b <- nowcast_backtest(
    s$tri,
    m,
    as_of_weeks = as_of,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    probs = probs,
    seed = 11
  )
  expect_gt(nrow(a), 0L)
  # same as_of, same seed -> identical draws, run after run
  expect_equal(a$predicted, b$predicted)
  # and the key is the date, not the position: reversing the list changes nothing
  rv <- nowcast_backtest(
    s$tri,
    m,
    as_of_weeks = rev(as_of),
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    probs = probs,
    seed = 11
  )
  data.table::setorder(rv, as_of, reference, quantile_level)
  a2 <- data.table::copy(a)
  data.table::setorder(a2, as_of, reference, quantile_level)
  expect_equal(rv$predicted, a2$predicted)
  # the other direction, so this test cannot pass by being inert: the seed must
  # actually reach the RNG
  other <- nowcast_backtest(
    s$tri,
    m,
    as_of_weeks = as_of,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    probs = probs,
    seed = 99
  )
  expect_false(isTRUE(all.equal(a$predicted, other$predicted)))
})

test_that("nowcast_evaluate_v1 backtests + scores a single method, deterministic by seed", {
  s <- sim_backtest_triangle()
  m <- function(x) {
    nowcast_delay_ecdf_v1(x, max_delay_days = s$max_delay_days, n_sim = 100)
  }
  ev1 <- nowcast_evaluate_v1(
    s$tri,
    m,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    seed = 42
  )
  ev2 <- nowcast_evaluate_v1(
    s$tri,
    m,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    seed = 42
  )

  expect_true(all(
    c(
      "method",
      "horizon",
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
      names(ev1)
  ))
  expect_setequal(ev1$horizon, 1:2)
  expect_true(all(ev1$coverage_90 >= 0 & ev1$coverage_90 <= 1))
  expect_equal(ev1$median_abs, ev2$median_abs) # same seed -> identical evaluation
})

test_that("nowcast_evaluate_v1 races several methods (paired) for the recommendation", {
  s <- sim_backtest_triangle()
  ev <- nowcast_evaluate_v1(
    s$tri,
    max_delay_days = s$max_delay_days,
    horizons = 1:2,
    seed = 1,
    methods = list(
      simple = function(x) {
        nowcast_delay_ecdf_v1(x, max_delay_days = s$max_delay_days, n_sim = 200)
      },
      passthrough = function(x) {
        nowcast_passthrough_to_ensemble_v1(x, max_delay_days = s$max_delay_days)
      }
    )
  )

  expect_setequal(unique(ev$method), c("simple", "passthrough"))
  # the nowcast should revise LESS than naive passthrough at the freshest horizon
  # (passthrough carries the still-incomplete count, so it under-predicts badly)
  w <- dcast(ev[horizon == 1], horizon ~ method, value.var = "median_abs")
  expect_lt(w$simple, w$passthrough)
})
