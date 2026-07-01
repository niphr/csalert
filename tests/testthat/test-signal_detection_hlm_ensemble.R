# HLM signal detection on the ensemble: baseline-from-history + per-draw classify.

mk_baseline_ensemble <- function(n_years = 8, n_draws = 6, lambda = 10, seed = 1) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2012-01")
  wk <- weeks[i0:(i0 + n_years * 52 - 1)]          # contiguous weekly series
  point <- stats::rpois(length(wk), lambda)
  M <- matrix(rep(point, n_draws), nrow = length(wk))
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = wk)
  list(ens = csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                               draws = list(rate = M)),
       wk = wk, point = point)
}

test_that("hlm attaches a threshold and an ordinal status matrix", {
  z <- mk_baseline_ensemble()
  out <- signal_detection_hlm(z$ens, measure = "rate", baseline_isoyears = 3)

  expect_true("hlm_threshold" %in% names(out$data))
  key <- csfmt_var("rate", role = "hlmstatus")
  expect_true(key %in% names(out$draws))
  code <- out$draws[[key]]
  expect_equal(attr(code, "levels"), c("null", "high"))
  expect_true(all(stats::na.omit(unique(as.vector(code))) %in% 1:2))
  # early weeks (no full baseline) -> NA threshold
  expect_true(any(is.na(out$data$hlm_threshold)))
})

test_that("a large spike above the baseline is classified high", {
  z <- mk_baseline_ensemble()
  # spike the last week far above the ~10 baseline
  spike <- max(z$ens$data$isoyearweek)
  z$ens$draws$rate[z$ens$data$isoyearweek == spike, ] <- 1000

  out <- signal_detection_hlm(z$ens, measure = "rate", baseline_isoyears = 3)
  key <- csfmt_var("rate", role = "hlmstatus")
  expect_equal(unique(out$draws[[key]][out$data$isoyearweek == spike, ]), 2L)  # high
})

test_that("hlm status collapses to exceedance probabilities", {
  z <- mk_baseline_ensemble()
  spike <- max(z$ens$data$isoyearweek)
  z$ens$draws$rate[z$ens$data$isoyearweek == spike, ] <- 1000
  out <- signal_detection_hlm(z$ens, measure = "rate", baseline_isoyears = 3) |>
    ens_collapse(probs = c(0.5))
  expect_true("rate_hlmstatus_prob_high" %in% names(out))
  expect_equal(out[out$isoyearweek == spike][["rate_hlmstatus_prob_high"]], 1)
})
