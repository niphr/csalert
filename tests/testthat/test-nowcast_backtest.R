# nowcast backtest/score/compare harness, on a simulated triangle with held-out
# truth. Mechanics (censor/truth/backtest) are tested without scoringutils; the
# scoring/compare wrappers run only when scoringutils is available.

# Simulate a KNOWN process: Poisson reference-week counts reported with a known
# decreasing delay, right-truncated at the latest week. Hold out the true totals.
sim_backtest_triangle <- function(n_weeks = 24, lambda = 80, max_delay = 4, seed = 7) {
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
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  list(tri = csfmt_reporting_triangle_v3(tri[], id_cols = c("indicator", "location", "age", "sex")),
       truth = data.table::data.table(reference = ref_weeks, truth = truth),
       weeks = weeks, i0 = i0, n_weeks = n_weeks, max_delay = max_delay)
}

test_that("nowcast_censor keeps only what was known as-of, and moves the boundary", {
  s <- sim_backtest_triangle()
  as_of <- s$weeks[s$i0 + 10]
  cens <- nowcast_censor(s$tri, as_of)
  rep_col <- attr(cens, "reporting_col")
  expect_true(all(cens[[rep_col]] <= as_of))
  expect_equal(attr(cens, "as_of"), max(cens[[rep_col]]))
  expect_true(attr(cens, "as_of") <= as_of)   # ISO-week strings compare lexically
  # censoring to the full as-of is a no-op on the cell set
  expect_equal(nrow(nowcast_censor(s$tri, attr(s$tri, "as_of"))), nrow(s$tri))
})

test_that("nowcast_truth recovers the settled totals for old-enough weeks", {
  s <- sim_backtest_triangle()
  tr <- nowcast_truth(s$tri, max_delay = s$max_delay)
  # only settled weeks are returned (older than max_delay from the as-of)
  expect_true(nrow(tr) < s$n_weeks)
  # and their totals equal the held-out truth (all cases fall within max_delay)
  chk <- merge(tr, s$truth, by = "reference", suffixes = c("_got", "_true"))
  expect_equal(chk$truth_got, chk$truth_true)
})

test_that("nowcast_backtest replays a method into a tidy long table", {
  s <- sim_backtest_triangle()
  passthrough <- function(x) nowcast_passthrough_to_ensemble(x, max_delay = s$max_delay)
  bt <- nowcast_backtest(s$tri, passthrough, max_delay = s$max_delay, horizons = 1:2)

  expect_true(all(c("reference", "as_of", "horizon", "quantile_level", "predicted") %in% names(bt)))
  expect_setequal(unique(bt$horizon), 1:2)
  # passthrough is a point mass -> every quantile equals the observed-so-far
  by_fc <- bt[, .(spread = diff(range(predicted))), by = .(reference, horizon)]
  expect_true(all(by_fc$spread == 0))
})

test_that("nowcast_score returns WIS + coverage by horizon", {
  skip_if_not_installed("scoringutils")
  s <- sim_backtest_triangle()
  passthrough <- function(x) nowcast_passthrough_to_ensemble(x, max_delay = s$max_delay)
  bt <- nowcast_backtest(s$tri, passthrough, max_delay = s$max_delay, horizons = 1:2)
  sc <- nowcast_score(bt, nowcast_truth(s$tri, s$max_delay))

  expect_true("wis" %in% names(sc$scores))
  expect_setequal(sc$scores$horizon, 1:2)
  expect_true(all(is.finite(sc$scores$wis)))
})

test_that("nowcast_compare ranks a real nowcast against the passthrough baseline", {
  skip_if_not_installed("scoringutils")
  skip_if_not_installed("flexsurv")
  s <- sim_backtest_triangle()
  card <- nowcast_compare(s$tri, max_delay = s$max_delay, horizons = 1:2,
    methods = list(
      simple      = function(x) nowcast_simple(x, max_delay = s$max_delay, n_sim = 200),
      passthrough = function(x) nowcast_passthrough_to_ensemble(x, max_delay = s$max_delay)))

  expect_true(all(c("method", "horizon", "wis") %in% names(card)))
  expect_setequal(unique(card$method), c("simple", "passthrough"))
  # the nowcast should beat naive passthrough on WIS at the freshest horizon
  # (passthrough carries the still-incomplete count, so it under-predicts badly)
  w <- dcast(card[horizon == 1], horizon ~ method, value.var = "wis")
  expect_lt(w$simple, w$passthrough)
})
