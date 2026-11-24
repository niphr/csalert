# delay_distribution_v1() and outage_weeks_v1(): known answers on hand-built
# triangles, and the same values as the luftveis originals, which this file
# sources read-only when the checkout is on this machine.

luftveis_file <- paste0(
  "C:/Users/RIWH/GitHub/luftveisovervaking_trend/",
  "R_examination_of_trend/nowcast_negbin_gam.R"
)

# A one-series triangle from cells: week (1 is the week of 2024-01-01), delay
# (days after the reference Monday) and n. Reports after as_of are dropped.
dc_triangle <- function(cells, as_of = NULL, location = "nation") {
  monday <- as.Date("2024-01-01") + 7L * (cells$week - 1L)
  d <- data.table::data.table(
    isoyearweek_reference = format(monday, "%G-%V"),
    reporting_date = monday + cells$delay,
    numerator = cells$n,
    indicator_tag = "x",
    location_code = location
  )
  if (!is.null(as_of)) {
    d <- d[reporting_date <= as_of]
  }
  return(csfmt_reporting_triangle_v3(
    d,
    id_cols = c("indicator_tag", "location_code")
  ))
}

# Weeks 1 to n_weeks, each with 8 cases on delay day 2 and 2 on delay day 12.
# An outage week has 1 on day 2 and 9 on day 12. A gap week has no report. The
# as-of date is delay day 2 of the newest week.
dc_outage_triangle <- function(n_weeks, outage = integer(), gap = integer()) {
  weeks <- setdiff(seq_len(n_weeks), gap)
  cells <- data.table::data.table(
    week = rep(weeks, each = 2L),
    delay = rep(c(2L, 12L), length(weeks)),
    n = rep(c(8, 2), length(weeks))
  )
  cells[week %in% outage, n := rep(c(1, 9), length(outage))]
  as_of <- as.Date("2024-01-01") + 7L * (n_weeks - 1L) + 2L
  return(dc_triangle(cells, as_of = as_of))
}

# Weeks 1 to 3 on delay days 0 to 2. The as-of date is delay day 1 of week 3,
# so week 3 has seen delay days 0 and 1 only.
dc_truncated_triangle <- function() {
  cells <- data.table::data.table(
    week = c(1L, 1L, 1L, 2L, 2L, 2L, 3L, 3L),
    delay = c(0L, 1L, 2L, 0L, 1L, 2L, 0L, 1L),
    n = c(10, 20, 10, 20, 10, 10, 50, 10)
  )
  return(dc_triangle(cells))
}

test_that("delay_distribution_v1 corrects a right-truncated week by hand", {
  tri <- dc_truncated_triangle()
  expect_equal(attr(tri, "as_of"), as.Date("2024-01-16"))
  dd <- delay_distribution_v1(tri, max_delay_days = 3L)
  expect_s3_class(dd, "data.table")
  expect_named(dd, c("delay", "day_after", "week_after", "p"))
  expect_identical(dd$delay, 0:2)
  # Product-limit, backwards from F(2) = 1. Weeks 1 and 2 have seen delay day
  # 2: they have 30 + 30 cases by day 1 and 40 + 40 by day 2. All three weeks
  # have seen delay day 1: 10 + 20 + 50 by day 0 and 30 + 30 + 60 by day 1.
  F1 <- (30 + 30) / (40 + 40)
  F0 <- F1 * (10 + 20 + 50) / (30 + 30 + 60)
  expect_equal(dd$p, c(F0, F1 - F0, 1 - F1))
  expect_equal(dd$p, c(0.5, 0.25, 0.25))
  # the share of the two fully reported weeks alone is a different answer
  expect_false(isTRUE(all.equal(dd$p, c(30, 30, 20) / 80)))
})

test_that("delay_distribution_v1 with max_delay_days = 1 gives p = 1", {
  dd <- delay_distribution_v1(dc_truncated_triangle(), max_delay_days = 1L)
  expect_identical(dd$delay, 0L)
  expect_equal(dd$p, 1)
})

test_that("delay_distribution_v1 gives day_after and week_after by delay day", {
  dd <- delay_distribution_v1(dc_truncated_triangle(), max_delay_days = 57L)
  at <- match(c(0L, 6L, 7L, 13L, 14L, 56L), dd$delay)
  expect_identical(dd$day_after[at], c(-6L, 0L, 1L, 7L, 8L, 50L))
  expect_identical(dd$week_after[at], c(0L, NA, 1L, NA, 2L, 8L))
})

test_that("outage_weeks_v1 flags the hand-built outage week", {
  # Weeks 1 to 5 are 5 or more weeks older than week 10 and have seen 14 delay
  # days. Their shares by day 9 are 0.8, 0.8, 0.1, 0.8 and 0.8, so the median
  # is 0.8, and only week 3 is below 0.5 * 0.8.
  out <- outage_weeks_v1(dc_outage_triangle(10L, outage = 3L), 14L)
  expect_s3_class(out, "data.table")
  expect_identical(out$isoyearweek_reference, "2024-03")
})

test_that("outage_weeks_v1 with no outage gives zero rows", {
  out <- outage_weeks_v1(dc_outage_triangle(10L), 14L)
  expect_s3_class(out, "data.table")
  expect_named(out, "isoyearweek_reference")
  expect_identical(nrow(out), 0L)
  expect_type(out$isoyearweek_reference, "character")
})

test_that("outage_weeks_v1 flags nothing with fewer than 4 candidate weeks", {
  # 9 weeks: weeks 1 to 4 are candidates, and week 2 is flagged
  out <- outage_weeks_v1(dc_outage_triangle(9L, outage = 2L), 14L)
  expect_identical(out$isoyearweek_reference, "2024-02")
  # 8 weeks: only weeks 1 to 3 are 5 or more weeks old
  out <- outage_weeks_v1(dc_outage_triangle(8L, outage = 2L), 14L)
  expect_identical(nrow(out), 0L)
  expect_named(out, "isoyearweek_reference")
  # 9 weeks, but week 4 has no report, so it is not a candidate
  out <- outage_weeks_v1(dc_outage_triangle(9L, outage = 2L, gap = 4L), 14L)
  expect_identical(nrow(out), 0L)
})

test_that("both functions stop on more than one series, naming the id columns", {
  # one report in each of two locations
  cells <- data.table::data.table(week = c(1L, 2L), delay = 0L, n = 1)
  tri <- dc_triangle(cells, location = c("a", "b"))
  expect_identical(data.table::uniqueN(tri$time_series_id), 2L)
  expect_error(
    delay_distribution_v1(tri, 3L),
    "id columns: indicator_tag, location_code",
    fixed = TRUE
  )
  expect_error(
    outage_weeks_v1(tri, 3L),
    "id columns: indicator_tag, location_code",
    fixed = TRUE
  )
})

# A random triangle of n_weeks weeks. Each week has Poisson(200) cases with a
# geometric delay in days. An outage week has every delay 12 days later. The
# as-of date is delay day as_of_day of the newest week.
dc_random_triangle <- function(seed, n_weeks, outage, gap, as_of_day) {
  set.seed(seed)
  rows <- list()
  for (w in setdiff(seq_len(n_weeks), gap)) {
    delay <- stats::rgeom(stats::rpois(1L, 200), 0.12)
    if (w %in% outage) {
      delay <- delay + 12L
    }
    rows[[length(rows) + 1L]] <- data.table::data.table(week = w, delay = delay)
  }
  cells <- data.table::rbindlist(rows)[,
    .(n = as.numeric(.N)),
    by = .(week, delay)
  ]
  as_of <- as.Date("2024-01-01") + 7L * (n_weeks - 1L) + as_of_day
  return(dc_triangle(cells, as_of = as_of))
}

test_that("both functions give the values of the luftveis originals", {
  skip_if_not(file.exists(luftveis_file))
  ref <- new.env()
  source(luftveis_file, local = ref)

  cases <- list(
    list(
      tri = dc_random_triangle(1L, 30L, outage = 12L, gap = integer(), 3L),
      max_delay_days = 21L
    ),
    list(
      tri = dc_random_triangle(2L, 40L, outage = c(10L, 25L), gap = 20L, 5L),
      max_delay_days = 35L
    )
  )
  args <- list(
    list(),
    list(early_days = 5L, min_weeks_back = 3L, frac = 0.7)
  )
  n_flagged <- 0L
  for (case in cases) {
    tri <- case$tri
    mdd <- case$max_delay_days
    m <- reporting_triangle_matrix(tri, mdd)[[1]]
    age_days <- as.integer(
      attr(tri, "as_of") - isoyearweek_week_start(m$reference)
    )
    k <- which(age_days >= 0L)
    n_seen <- pmin(age_days[k] + 1L, mdd)
    rt <- m$mat[k, , drop = FALSE]
    # right truncation: the newest weeks have seen fewer than mdd delay days
    expect_gt(sum(n_seen < mdd), 1L)
    # and there are reports past the horizon
    expect_gt(sum(m$late), 0)

    dd <- delay_distribution_v1(tri, mdd)
    expect_identical(dd$delay, seq_len(mdd) - 1L)
    expect_equal(dd$p, ref$.delay_probs_truncated(rt, n_seen))

    for (a in args) {
      out <- do.call(outage_weeks_v1, c(list(tri, mdd), a))
      want <- m$reference[k][do.call(ref$.outage_weeks, c(list(rt, n_seen), a))]
      expect_identical(out$isoyearweek_reference, want)
      n_flagged <- n_flagged + length(want)
    }
  }
  # the comparison of the flagged weeks is not of empty sets only
  expect_gte(n_flagged, 4L)
})
