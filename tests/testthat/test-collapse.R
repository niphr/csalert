# collapse: ensemble -> quantile-summary.

test_that("collapse adds named quantile columns and drops the draws", {
  set.seed(1)
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = c("2020-01", "2020-02"))
  M <- matrix(stats::rpois(2 * 1000, 50), nrow = 2)
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = M))

  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  expect_s3_class(out, "data.table")
  expect_true(all(c("cases_q02x5", "cases_q50x0", "cases_q97x5") %in% names(out)))
  expect_false("draws" %in% names(out))   # plain data.table, no draws
})

test_that("collapse quantiles match a direct rowQuantiles", {
  set.seed(2)
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = sprintf("2020-%02d", 1:5))
  M <- matrix(stats::rpois(5 * 1000, 40), nrow = 5)
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = M))

  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  rq <- matrixStats::rowQuantiles(ens$draws$cases, probs = c(0.025, 0.5, 0.975))
  expect_equal(out$cases_q50x0, rq[, 2])
  expect_equal(out$cases_q02x5, rq[, 1])
  expect_equal(out$cases_q97x5, rq[, 3])
})

test_that("ens_collapse(heal = TRUE) heals into a clean csfmt_rts_data_v3", {
  skip_if_not_installed("cstidy")
  set.seed(4)
  d <- data.table::data.table(location_code = "norge", age = "total", sex = "total",
                              isoyearweek = c("2022-01", "2022-02"))
  M <- matrix(stats::rpois(2 * 100, 50), nrow = 2)
  ens <- csfmt_ensemble_v3(d, id_cols = c("location_code", "age", "sex"),
                           draws = list(cases = M))

  out <- ens_collapse(ens, probs = 0.5, heal = TRUE)
  expect_s3_class(out, "csfmt_rts_data_v3")
  expect_true(all(c("isoyear", "season", "granularity_geo") %in% names(out)))
  expect_false(any(is.na(out$isoyear)))               # healed from isoyearweek
  expect_equal(unique(out$granularity_geo), "nation") # healed from location_code
  expect_true("cases_q50x0" %in% names(out))
})

test_that("collapse handles multiple measures (nowcast + trend)", {
  set.seed(3)
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  n <- length(wk)
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = wk)
  M <- matrix(stats::rpois(n * 200, 40), nrow = n)
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                        draws = list(cases = M))
  ens <- short_term_trend(ens, measure = "cases", trend_isoyearweeks = 3)

  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  expect_true(all(c("cases_q50x0", "cases_trend_gr_q50x0", "cases_trend_beta1_q50x0")
                  %in% names(out)))
  expect_equal(nrow(out), n)
})
