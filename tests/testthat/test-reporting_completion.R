# reporting_completion_v1: recover a known reporting-delay curve from a triangle.
#
# The delay axis is DAYS. The simulation still draws a delay in whole weeks, then
# lands the report on the Monday that many weeks after the reference Monday. So a
# known weekly curve of .4 .3 .2 .1 becomes steps at delay days 0, 7, 14 and 21,
# and max_delay_days = 28 covers all four.

test_that("reporting_completion_v1 recovers the known delay curve + quartiles", {
  set.seed(4)
  max_delay_days <- 28L
  n_weeks <- 60
  mondays <- as.Date("2019-12-30") + 7L * (seq_len(n_weeks) - 1L)
  dp <- c(.4, .3, .2, .1) # known cumulative: .4 .7 .9 1.0
  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 200)
    del <- sample(0:3, n, replace = TRUE, prob = dp)
    rows[[w]] <- data.table::data.table(
      isoyearweek_reference = format(mondays[w], "%G-%V"),
      reporting_date = mondays[w] + 7L * del
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
  tri <- csfmt_reporting_triangle_v3(
    tri[],
    id_cols = c("indicator", "location", "age", "sex")
  )

  rc <- reporting_completion_v1(tri, max_delay_days = max_delay_days)
  expect_equal(nrow(rc), 1L)
  # 0-based and indexed by DELAY DAY: max_delay_days = 28 gives delay days 0..27,
  # so there are 28 pct_delay columns and the highest is pct_delay27.
  expect_equal(sum(grepl("^pct_delay", names(rc))), max_delay_days)
  expect_true(all(paste0("pct_delay", 0:27) %in% names(rc)))
  expect_false("pct_delay28" %in% names(rc))
  expect_false(any(grepl("^pct_w[0-9]", names(rc))))
  expect_equal(rc$period, "all")
  expect_equal(rc$complete_by_md, 1, tolerance = 0.02) # ~all in by max_delay_days
  # mean delay in DAYS: 0*.4 + 7*.3 + 14*.2 + 21*.1 = 7.0
  expect_equal(rc$mean_delay, 7.0, tolerance = 0.15)
  # delay ECDF: known cumulative .4 .7 .9 1.0 -> pct_delayD ~ 40, 70, 90, 100 at
  # delay days 0, 7, 14 and 21
  expect_equal(rc$pct_delay0, 40, tolerance = 6) # ~40% in on the reference Monday
  expect_equal(rc$pct_delay7, 70, tolerance = 6) # ~70% by a week later
  expect_equal(rc$pct_delay14, 90, tolerance = 6) # ~90% by two weeks later
  expect_equal(rc$pct_delay21, 100, tolerance = 2) # ~all by three weeks later
  # nothing arrives between two reporting Mondays, so the curve is flat there
  expect_equal(rc$pct_delay6, rc$pct_delay0)
  expect_equal(rc$pct_delay13, rc$pct_delay7)
  # monotone across the whole day axis
  curve <- unlist(rc[, paste0("pct_delay", 0:27), with = FALSE])
  expect_true(all(diff(curve) >= 0))

  # period stratification: the ~60-week span covers >1 calendar year and several
  # months -> multiple rows, each a valid summary, labelled by period.
  by_year <- reporting_completion_v1(
    tri,
    max_delay_days = max_delay_days,
    period = "year"
  )
  expect_gt(nrow(by_year), 1L)
  expect_true(all(grepl("^[0-9]{4}$", by_year$period)))
  expect_true(all(
    by_year$mean_delay > 0 & by_year$mean_delay < max_delay_days
  ))

  by_month <- reporting_completion_v1(
    tri,
    max_delay_days = max_delay_days,
    period = "month"
  )
  expect_gt(nrow(by_month), nrow(by_year))
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", by_month$period)))

  # trend convenience: year rows + last-N month rows, tagged by scope
  tr <- reporting_completion_trend_v1(
    tri,
    max_delay_days = max_delay_days,
    n_months = 3L
  )
  expect_true("scope" %in% names(tr))
  expect_setequal(unique(tr$scope), c("year", "month"))
  expect_equal(sum(tr$scope == "year"), nrow(by_year)) # all years kept
  expect_lte(sum(tr$scope == "month"), 3L) # months capped at n_months
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", tr[scope == "month"]$period)))
})

# max_delay_days = 1 is a single delay column. apply(, 1, cumsum) returns a VECTOR
# there rather than a matrix, so the old t() produced a 1 x n_settled matrix and
# the function emitted one pct_delay column per settled WEEK, with a
# complete_by_md far below 1. Silently wrong, no error.
test_that("reporting_completion_v1 handles a single delay column", {
  mondays <- as.Date("2023-01-02") + 7L * (0:29)
  ref <- format(mondays, "%G-%V")
  d <- data.table::data.table(
    isoyearweek_reference = rep(ref, each = 2),
    reporting_date = rep(mondays, each = 2) + rep(c(0L, 7L), 30),
    numerator = rep(c(60, 40), 30),
    indicator = "test",
    location = "nation",
    age = "total",
    sex = "total"
  )
  d <- d[reporting_date <= mondays[30]]
  tri <- csfmt_reporting_triangle_v3(
    d[],
    id_cols = c("indicator", "location", "age", "sex")
  )

  rc1 <- reporting_completion_v1(tri, max_delay_days = 1)
  expect_equal(nrow(rc1), 1L)
  # exactly ONE completion column, named for delay day 0
  expect_equal(sum(grepl("^pct_delay", names(rc1))), 1L)
  expect_true("pct_delay0" %in% names(rc1))
  # everything within the horizon is by definition in by the end of the horizon
  expect_equal(rc1$complete_by_md, 1)
  expect_equal(rc1$pct_delay0, 100)
  expect_equal(rc1$mean_delay, 0) # only delay day 0 survives truncation

  # the column count must equal max_delay_days at every horizon
  for (md in c(1L, 7L, 8L, 14L, 35L)) {
    rc <- reporting_completion_v1(tri, max_delay_days = md)
    expect_equal(sum(grepl("^pct_delay", names(rc))), md)
    expect_equal(rc$complete_by_md, 1, tolerance = 0.02)
  }

  # the documented contract change: a former 5 weekly columns is now 35 daily
  # ones, because max_delay_days counts days
  rc35 <- reporting_completion_v1(tri, max_delay_days = 35)
  expect_equal(sum(grepl("^pct_delay", names(rc35))), 35L)
  expect_true("pct_delay34" %in% names(rc35))
  expect_false("pct_delay35" %in% names(rc35))
  # delay day 7 carries the second report, so the curve steps there and nowhere
  # else inside the horizon
  expect_equal(rc35$pct_delay0, 60)
  expect_equal(rc35$pct_delay6, 60)
  expect_equal(rc35$pct_delay7, 100)
  expect_equal(rc35$mean_delay, 2.8) # 0*.6 + 7*.4
})
