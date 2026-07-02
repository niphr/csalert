# Categorical/ordinal status collapse (Gap 1): prob-per-level + ordinal quantiles.

test_that("collapse reduces an ordinal status matrix to probs + ordinal quantiles", {
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = c("2020-01", "2020-02"))
  # row1 draws: [1,1,3,3,3] -> P(preepidemic)=0.4, P(medium)=0.6, ordinal median=3
  # row2 draws: all 5 (veryhigh)
  code <- matrix(c(1, 1, 3, 3, 3,
                   5, 5, 5, 5, 5), nrow = 2, byrow = TRUE)
  attr(code, "levels") <- c("preepidemic", "low", "medium", "high", "veryhigh")
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                           draws = list(rate_status = code))

  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))

  # probability per level
  expect_equal(out$rate_status_prob_preepidemic, c(0.4, 0))
  expect_equal(out$rate_status_prob_medium,      c(0.6, 0))
  expect_equal(out$rate_status_prob_veryhigh,    c(0,   1))
  # probabilities sum to 1 per row
  pcols <- grep("_prob_", names(out), value = TRUE)
  expect_equal(rowSums(as.matrix(out[, ..pcols])), c(1, 1))

  # ordinal quantiles (codes): median row1 = medium(3), row2 = veryhigh(5)
  expect_equal(out$rate_status_q50x0, c(3, 5))
  expect_equal(out$rate_status_q02x5, c(1, 5))   # 2.5% lower: preepidemic / veryhigh
  expect_equal(out$rate_status_q97x5, c(3, 5))
})

test_that("status collapse composes after mem on a real ensemble", {
  skip_if_not_installed("mem")
  set.seed(1)
  iyw <- cstime::date_to_isoyearweek_c(as.Date("2008-08-04") + 7 * (0:(12 * 53 - 1)))
  season <- cstime::isoyearweek_to_season_c(iyw)
  cnt <- table(season); keep <- sort(names(cnt)[cnt >= 50])[1:10]
  iyw <- iyw[season %in% keep]
  w <- as.integer(substr(iyw, 6, 7)); dist <- pmin(abs(w - 1), abs(w - 53))
  point <- pmax(0, 1 + 30 * exp(-(dist^2) / 50) + stats::rnorm(length(iyw), 0, 0.3))
  M <- matrix(rep(point, 50), nrow = length(iyw))   # 50 draws

  ens <- csfmt_ensemble_v3(
    data.table::data.table(indicator = "flu", location = "nation", age = "total", isoyearweek = iyw),
    id_cols = c("indicator", "location", "age"), draws = list(rate = M))
  ens <- mem_thresholds_v1(ens, measure = "rate")
  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))

  expect_true(any(grepl("rate_status_prob_", names(out))))
  expect_true("rate_status_q50x0" %in% names(out))
  expect_true(all(stats::na.omit(out$rate_status_q50x0) %in% 1:5))
})
