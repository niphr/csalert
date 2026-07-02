# reporting_completion: recover a known reporting-delay curve from a triangle.

test_that("reporting_completion recovers the known delay curve + quartiles", {
  set.seed(4)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek; i0 <- which(weeks == "2020-01")
  max_delay <- 4; n_weeks <- 60
  dp <- c(.4, .3, .2, .1)                                  # known cumulative: .4 .7 .9 1.0
  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 200)
    del <- sample(0:(max_delay - 1), n, replace = TRUE, prob = dp)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = weeks[i0 + w - 1],
                                        rep_idx = (i0 + w - 1) + del)
  }
  ll <- data.table::rbindlist(rows); ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  tri <- csfmt_reporting_triangle_v3(tri[], id_cols = c("indicator", "location", "age", "sex"))

  rc <- reporting_completion(tri, max_delay = max_delay)
  expect_equal(nrow(rc), 1L)
  expect_true(all(c("period", "mean_delay", "complete_by_md",
                    "pct_w1", "pct_w2", "pct_w3", "pct_w4") %in% names(rc)))
  expect_equal(rc$period, "all")
  expect_equal(rc$complete_by_md, 1, tolerance = 0.02)     # ~all in by max_delay
  expect_equal(rc$mean_delay, 1.0, tolerance = 0.15)       # 0*.4+1*.3+2*.2+3*.1 = 1.0
  # delay ECDF: known cumulative .4 .7 .9 1.0 -> pct_wN ~ 40, 70, 90, 100
  expect_equal(rc$pct_w1, 40, tolerance = 6)               # ~40% in after 1 week
  expect_equal(rc$pct_w2, 70, tolerance = 6)               # ~70% after 2 weeks
  expect_equal(rc$pct_w3, 90, tolerance = 6)               # ~90% after 3 weeks
  expect_equal(rc$pct_w4, 100, tolerance = 2)              # ~all after 4 weeks
  expect_true(all(diff(c(rc$pct_w1, rc$pct_w2, rc$pct_w3, rc$pct_w4)) >= 0))  # monotone

  # period stratification: the ~60-week span covers >1 calendar year and several
  # months -> multiple rows, each a valid summary, labelled by period.
  by_year <- reporting_completion(tri, max_delay = max_delay, period = "year")
  expect_gt(nrow(by_year), 1L)
  expect_true(all(grepl("^[0-9]{4}$", by_year$period)))
  expect_true(all(by_year$mean_delay > 0 & by_year$mean_delay < max_delay))

  by_month <- reporting_completion(tri, max_delay = max_delay, period = "month")
  expect_gt(nrow(by_month), nrow(by_year))
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", by_month$period)))

  # trend convenience: year rows + last-N month rows, tagged by scope
  tr <- reporting_completion_trend_v1(tri, max_delay = max_delay, n_months = 3L)
  expect_true("scope" %in% names(tr))
  expect_setequal(unique(tr$scope), c("year", "month"))
  expect_equal(sum(tr$scope == "year"), nrow(by_year))     # all years kept
  expect_lte(sum(tr$scope == "month"), 3L)                 # months capped at n_months
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", tr[scope == "month"]$period)))
})
