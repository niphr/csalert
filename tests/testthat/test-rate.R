# add_rate: per-draw rate measure with denom=0 -> NA and coherence cap.

mk_numdenom <- function() {
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = c("2020-01", "2020-02", "2020-03"))
  num <- matrix(c(2, 4,   5, 5,   0, 0), nrow = 3, byrow = TRUE)   # 2 draws/week
  den <- matrix(c(10, 8,  10, 10, 0, 0), nrow = 3, byrow = TRUE)   # week3: denom 0
  csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                    draws = list(numerator = num, denominator = den))
}

test_that("add_rate computes per-draw rate with grammar name", {
  ens <- add_rate(mk_numdenom(), "numerator", "denominator", per = 100)
  key <- csfmt_var("numerator", denom = "denominator", per = 100)
  expect_true(key %in% names(ens$draws))
  r <- ens$draws[[key]]
  expect_equal(r[1, ], c(20, 50))            # 2/10*100, 4/8*100
})

test_that("denom = 0 yields NA (not a fabricated 0%)", {
  ens <- add_rate(mk_numdenom(), "numerator", "denominator", per = 100)
  r <- ens$draws[[csfmt_var("numerator", denom = "denominator", per = 100)]]
  expect_true(all(is.na(r[3, ])))            # week 3 denom 0 -> NA
})

test_that("rate is capped at per and warns on num > denom", {
  d <- data.table::data.table(indicator = "flu", location = "nation", age = "total",
                              isoyearweek = "2020-01")
  ens <- csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"),
                           draws = list(numerator = matrix(15, 1, 2),
                                        denominator = matrix(10, 1, 2)))
  expect_warning(ens <- add_rate(ens, "numerator", "denominator", per = 100),
                 "numerator > denominator")
  r <- ens$draws[[csfmt_var("numerator", denom = "denominator", per = 100)]]
  expect_true(all(r == 100))                 # capped
})
