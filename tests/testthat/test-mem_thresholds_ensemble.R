# MEM thresholds on the ensemble: fit-from-history + per-draw classify.

skip_if_not_installed("mem")

# weekly ensemble with a known seasonal epidemic (low summer, winter peak)
mk_seasonal_ensemble <- function(n_seasons = 10, n_draws = 6, baseline = 1, peak = 30,
                                 sigma = 5, noise_sd = 0.3, seed = 1) {
  set.seed(seed)
  # generate over a wide span, keep only COMPLETE seasons (>=50 weeks) -- a partial
  # boundary season would make na.omit truncate every season and break MEM.
  iyw <- cstime::date_to_isoyearweek_c(as.Date("2008-08-04") + 7 * (0:((n_seasons + 2) * 53 - 1)))
  season <- cstime::isoyearweek_to_season_c(iyw)
  cnt <- table(season)
  keep <- sort(names(cnt)[cnt >= 50])[seq_len(min(n_seasons, sum(cnt >= 50)))]
  iyw <- iyw[season %in% keep]

  w <- as.integer(substr(iyw, 6, 7))
  dist <- pmin(abs(w - 1), abs(w - 53))
  point <- pmax(0, baseline + peak * exp(-(dist^2) / (2 * sigma^2)) +
                  stats::rnorm(length(iyw), 0, noise_sd))
  M <- matrix(rep(point, n_draws), nrow = length(iyw))   # degenerate draws == point
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = iyw)
  list(ens = csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                            draws = list(rate = M)),
       wk = iyw)
}

test_that("thresholds are attached, ordered, and leave-future-out", {
  z <- mk_seasonal_ensemble()
  out <- mem_thresholds(z$ens, measure = "rate")

  expect_true(all(c("mem_preepidemic", "mem_medium", "mem_high", "mem_veryhigh")
                  %in% names(out$data)))
  thr <- stats::na.omit(unique(out$data[, .(mem_preepidemic, mem_medium, mem_high, mem_veryhigh)]))
  expect_gt(nrow(thr), 0)
  expect_true(all(thr$mem_preepidemic <= thr$mem_medium))
  expect_true(all(thr$mem_medium     <= thr$mem_high))
  expect_true(all(thr$mem_high       <= thr$mem_veryhigh))

  # leave-future-out: the earliest season has no prior history -> NA thresholds
  out$data[, .s := cstime::isoyearweek_to_season_c(isoyearweek)]
  first_season <- min(out$data$.s)
  expect_true(all(is.na(out$data[.s == first_season]$mem_preepidemic)))
})

test_that("status code matrix is produced with valid ordinal codes", {
  z <- mk_seasonal_ensemble()
  out <- mem_thresholds(z$ens, measure = "rate")
  status_key <- csfmt_var("rate", role = "status")
  expect_true(status_key %in% names(out$draws))

  code <- out$draws[[status_key]]
  expect_equal(dim(code), dim(out$draws$rate))
  vals <- unique(as.vector(code))
  expect_true(all(stats::na.omit(vals) %in% 1:5))
  expect_equal(attr(code, "levels"),
               c("preepidemic", "low", "medium", "high", "veryhigh"))
})

test_that("winter peak classifies elevated, summer as preepidemic", {
  z <- mk_seasonal_ensemble()
  out <- mem_thresholds(z$ens, measure = "rate")
  code <- out$draws[[csfmt_var("rate", role = "status")]]
  wk <- out$data$isoyearweek
  w  <- as.integer(substr(wk, 6, 7))
  s  <- cstime::isoyearweek_to_season_c(wk)

  # restrict to a season that actually has thresholds
  has_thr <- !is.na(out$data$mem_preepidemic)
  winter <- has_thr & w %in% c(52, 1, 2)
  summer <- has_thr & w %in% c(28, 30, 32)
  expect_true(any(code[winter, 1] >= 3, na.rm = TRUE))         # medium+ in deep winter
  expect_gt(mean(code[summer, 1] == 1, na.rm = TRUE), 0.8)     # preepidemic in summer
})
