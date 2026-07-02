# nowcast_quasipoisson_v1: chain-ladder GLM nowcast with simulated draws (base
# stats only -- no flexsurv). Structural + sanity checks against a known process.

sim_qp_triangle <- function(n_weeks = 22, lambda = 70, max_delay = 4, seed = 2) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek; i0 <- which(weeks == "2020-01")
  ref_weeks <- weeks[i0:(i0 + n_weeks - 1)]; dp <- (max_delay:1) / sum(max_delay:1)
  rows <- list(); truth <- integer(n_weeks)
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, lambda); truth[w] <- n; if (n == 0) next
    del <- sample(0:(max_delay - 1), n, replace = TRUE, prob = dp)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        rep_idx = (i0 + w - 1) + del)
  }
  ll <- data.table::rbindlist(rows); ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  list(tri = csfmt_reporting_triangle_v3(tri[], id_cols = c("indicator", "location", "age", "sex")),
       truth = data.table::data.table(isoyearweek = ref_weeks, truth = truth))
}

test_that("nowcast_quasipoisson_v1 returns an ensemble with nowcasted draws", {
  s <- sim_qp_triangle()
  ens <- nowcast_quasipoisson_v1(s$tri, max_delay = 4, n_sim = 200)
  expect_s3_class(ens, "csfmt_ensemble_v3")
  expect_true("numerator_nowcasted" %in% names(ens$draws))
  expect_equal(nrow(ens$draws$numerator_nowcasted), nrow(ens$data))
  expect_equal(ncol(ens$draws$numerator_nowcasted), 200L)
  expect_true(all(ens$draws$numerator_nowcasted >= 0))
})

test_that("the median nowcast is >= the observed-so-far (completion adds cases)", {
  s <- sim_qp_triangle()
  out <- ens_collapse(nowcast_quasipoisson_v1(s$tri, max_delay = 4, n_sim = 300), probs = 0.5)
  expect_true(all(out[["numerator_nowcasted_q50x0"]] >= out$original - 1e-9))
})

test_that("recent (incomplete) weeks are inflated; settled weeks are not", {
  s <- sim_qp_triangle(n_weeks = 20, max_delay = 4)
  ens <- nowcast_quasipoisson_v1(s$tri, max_delay = 4, n_sim = 300)
  m <- ens$draws$numerator_nowcasted
  spread <- apply(m, 1, function(r) diff(range(r)))
  # the last few weeks are still reporting -> non-degenerate draws;
  # the earliest weeks are settled -> a point mass (zero spread)
  expect_gt(spread[length(spread)], 0)
  expect_equal(spread[1], 0)
})
