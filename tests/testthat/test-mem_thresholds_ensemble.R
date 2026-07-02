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
  out <- mem_thresholds_v1(z$ens, measure = "rate")

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

  # provisional tracking (ported from luftveis add_mem_thresholds_v1)
  expect_true("mem_n_seasons" %in% names(out$data))
  expect_true(all(stats::na.omit(out$data$mem_n_seasons) >= 2))
})

test_that("exclude_seasons drops seasons from the training baseline", {
  # NB mem_thresholds_v1 mutates $data by reference, so each call gets a FRESH
  # ensemble (same seed -> identical data, independent objects).
  n_for_last <- function(out) {
    out$data[, .s := cstime::isoyearweek_to_season_c(isoyearweek)]
    unique(out$data[.s == max(.s)]$mem_n_seasons)
  }
  base <- mem_thresholds_v1(mk_seasonal_ensemble(n_seasons = 10)$ens, measure = "rate")
  base$data[, .s := cstime::isoyearweek_to_season_c(isoyearweek)]
  seasons <- sort(unique(base$data$.s))
  last  <- max(seasons)
  drop1 <- seasons[length(seasons) - 1L]            # a prior season of `last`
  n_base <- unique(base$data[.s == last]$mem_n_seasons)

  # `last` trains on one fewer season once `drop1` is excluded
  ex <- mem_thresholds_v1(mk_seasonal_ensemble(n_seasons = 10)$ens, measure = "rate",
                       exclude_seasons = drop1)
  expect_equal(n_for_last(ex), n_base - 1L)

  # the excluded season itself is still thresholded (from its remaining priors)
  ex$data[, .s := cstime::isoyearweek_to_season_c(isoyearweek)]
  expect_false(all(is.na(ex$data[.s == drop1]$mem_preepidemic)))

  # excluding a non-existent season is a harmless no-op
  noop <- mem_thresholds_v1(mk_seasonal_ensemble(n_seasons = 10)$ens, measure = "rate",
                         exclude_seasons = "1990/1991")
  expect_equal(n_for_last(noop), n_base)
})

test_that("training is capped to the most recent i.seasons (before na.omit)", {
  # With more complete seasons than i.seasons, a late season must train on exactly
  # i.seasons -- and na.omit must apply only to those, not to older seasons that
  # memmodel would never use (else partial old seasons starve the fit -> NA).
  z <- mk_seasonal_ensemble(n_seasons = 13)
  out <- mem_thresholds_v1(z$ens, measure = "rate", i.seasons = 10)
  out$data[, .s := cstime::isoyearweek_to_season_c(isoyearweek)]
  last <- max(out$data$.s)
  expect_equal(unique(out$data[.s == last]$mem_n_seasons), 10L)   # capped, not 12
  expect_false(all(is.na(out$data[.s == last]$mem_preepidemic)))  # and still fits
})

test_that("sparse (near all-zero) seasons skip cleanly -> NA, no error/noise", {
  iyw <- cstime::date_to_isoyearweek_c(as.Date("2010-08-02") + 7 * (0:(5 * 53 - 1)))
  d <- data.table::data.table(indicator = "x", location = "n", age = "total",
                              sex = "total", isoyearweek = iyw)
  M <- matrix(0, nrow = nrow(d), ncol = 6)            # whole seasons, all zero
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator","location","age","sex"),
                           draws = list(rate = M))
  expect_error(out <- mem_thresholds_v1(ens, measure = "rate"), NA)   # no error
  expect_true(all(is.na(out$data$mem_preepidemic)))                # all NA thresholds

  # one season with signal is still < 2 -> still NA (needs >= 2 non-zero seasons)
  M2 <- matrix(0, nrow = nrow(d), ncol = 6)
  s1 <- cstime::isoyearweek_to_season_c(iyw); rows <- s1 == sort(unique(s1))[2]
  M2[rows, ] <- 5
  ens2 <- csfmt_ensemble_v3(d, id_cols = c("indicator","location","age","sex"),
                            draws = list(rate = M2))
  out2 <- mem_thresholds_v1(ens2, measure = "rate")
  expect_true(all(is.na(out2$data$mem_preepidemic)))
})

test_that("status code matrix is produced with valid ordinal codes", {
  z <- mk_seasonal_ensemble()
  out <- mem_thresholds_v1(z$ens, measure = "rate")
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
  out <- mem_thresholds_v1(z$ens, measure = "rate")
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
