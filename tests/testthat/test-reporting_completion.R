# reporting_completion_v1: recover a known reporting-delay curve from a triangle.

test_that("reporting_completion_v1 recovers the known delay curve + quartiles", {
  set.seed(4)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2020-01")
  max_delay <- 4
  n_weeks <- 60
  dp <- c(.4, .3, .2, .1) # known cumulative: .4 .7 .9 1.0
  rows <- list()
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, 200)
    del <- sample(0:(max_delay - 1), n, replace = TRUE, prob = dp)
    rows[[w]] <- data.table::data.table(
      isoyearweek_reference = weeks[i0 + w - 1],
      rep_idx = (i0 + w - 1) + del
    )
  }
  ll <- data.table::rbindlist(rows)
  ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]
  tri <- ll[,
    .(numerator = .N),
    by = .(isoyearweek_reference, isoyearweek_reporting)
  ]
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

  rc <- reporting_completion_v1(tri, max_delay = max_delay)
  expect_equal(nrow(rc), 1L)
  expect_true(all(
    c(
      "period",
      "mean_delay",
      "complete_by_md",
      "pct_delay0",
      "pct_delay1",
      "pct_delay2",
      "pct_delay3"
    ) %in%
      names(rc)
  ))
  # 0-based and indexed by DELAY: max_delay = 4 gives delays 0..3, so the highest
  # column is pct_delay3, NOT pct_delay4. The old pct_wN names were 1-based and
  # pct_w1 held delay 0, which read as "the week after" to anyone eyeing the triangle.
  expect_false(any(grepl("^pct_w[0-9]", names(rc))))
  expect_false("pct_delay4" %in% names(rc))
  expect_equal(rc$period, "all")
  expect_equal(rc$complete_by_md, 1, tolerance = 0.02) # ~all in by max_delay
  expect_equal(rc$mean_delay, 1.0, tolerance = 0.15) # 0*.4+1*.3+2*.2+3*.1 = 1.0
  # delay ECDF: known cumulative .4 .7 .9 1.0 -> pct_delayD ~ 40, 70, 90, 100
  expect_equal(rc$pct_delay0, 40, tolerance = 6) # ~40% in during the reference week itself
  expect_equal(rc$pct_delay1, 70, tolerance = 6) # ~70% by the end of the week after
  expect_equal(rc$pct_delay2, 90, tolerance = 6) # ~90% by two weeks after
  expect_equal(rc$pct_delay3, 100, tolerance = 2) # ~all by three weeks after
  expect_true(all(
    diff(c(rc$pct_delay0, rc$pct_delay1, rc$pct_delay2, rc$pct_delay3)) >= 0
  )) # monotone

  # period stratification: the ~60-week span covers >1 calendar year and several
  # months -> multiple rows, each a valid summary, labelled by period.
  by_year <- reporting_completion_v1(
    tri,
    max_delay = max_delay,
    period = "year"
  )
  expect_gt(nrow(by_year), 1L)
  expect_true(all(grepl("^[0-9]{4}$", by_year$period)))
  expect_true(all(by_year$mean_delay > 0 & by_year$mean_delay < max_delay))

  by_month <- reporting_completion_v1(
    tri,
    max_delay = max_delay,
    period = "month"
  )
  expect_gt(nrow(by_month), nrow(by_year))
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", by_month$period)))

  # trend convenience: year rows + last-N month rows, tagged by scope
  tr <- reporting_completion_trend_v1(tri, max_delay = max_delay, n_months = 3L)
  expect_true("scope" %in% names(tr))
  expect_setequal(unique(tr$scope), c("year", "month"))
  expect_equal(sum(tr$scope == "year"), nrow(by_year)) # all years kept
  expect_lte(sum(tr$scope == "month"), 3L) # months capped at n_months
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}$", tr[scope == "month"]$period)))
})

# max_delay = 1 is a single delay column. apply(, 1, cumsum) returns a VECTOR
# there rather than a matrix, so the old t() produced a 1 x n_settled matrix and
# the function emitted one pct_delay column per settled WEEK, with a
# complete_by_md far below 1. Silently wrong, no error.
test_that("reporting_completion_v1 handles a single delay column", {
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i <- match("2023-01", weeks)
  d <- data.table::data.table(
    isoyearweek_reference = weeks[i + rep(0:29, each = 2)],
    isoyearweek_reporting = weeks[i + rep(0:29, each = 2) + rep(0:1, 30)],
    numerator = rep(c(60, 40), 30),
    indicator = "test", location = "nation", age = "total", sex = "total"
  )
  d <- d[isoyearweek_reporting <= weeks[i + 29]]
  tri <- csfmt_reporting_triangle_v3(
    d[], id_cols = c("indicator", "location", "age", "sex")
  )

  rc1 <- reporting_completion_v1(tri, max_delay = 1)
  expect_equal(nrow(rc1), 1L)
  # exactly ONE completion column, named for delay 0
  expect_equal(sum(grepl("^pct_delay", names(rc1))), 1L)
  expect_true("pct_delay0" %in% names(rc1))
  # everything within the horizon is by definition in by the end of the horizon
  expect_equal(rc1$complete_by_md, 1)
  expect_equal(rc1$pct_delay0, 100)
  expect_equal(rc1$mean_delay, 0)  # only delay 0 survives truncation

  # the column count must equal max_delay at every horizon
  for (md in 1:4) {
    rc <- reporting_completion_v1(tri, max_delay = md)
    expect_equal(sum(grepl("^pct_delay", names(rc))), md)
    expect_equal(rc$complete_by_md, 1, tolerance = 0.02)
  }
})
