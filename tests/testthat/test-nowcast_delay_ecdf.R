# nowcast_delay_ecdf_v1: the daily delay ECDF engine. Structural checks, the two
# unit-mix boundaries, and the empirical interval endpoints.

ID_COLS <- c("indicator", "location", "age", "sex")

# n_sim = 2001 makes the endpoint identity EXACT rather than close.
# stats::quantile type 7 reads probability p at position (n - 1) * p + 1. With
# n = 2001 that is 101 for p = 0.05 and 1901 for p = 0.95, both whole numbers,
# so no interpolation happens and the draw at that position is the pool
# quantile itself. Any other n_sim leaves the identity true only up to the grid.
N_EXACT <- 2001L

# A single-series triangle. Every reference week draws a Poisson total, then
# spreads it over delay days 0 to max_delay_days - 1 with the same discretised
# gamma. The delay distribution does not change over time, so the pooled ECDF is
# the right estimator here and a bias the tests find comes from the code.
sim_ecdf_triangle <- function(
  n_weeks = 45L,
  max_delay_days = 35L,
  lambda = 600,
  observed_days = 2L,
  seed = 4L,
  identical_weeks = FALSE
) {
  set.seed(seed)
  cal <- cstime::dates_by_isoyearweek
  i0 <- match("2022-01", cal$isoyearweek)
  idx <- i0 + seq_len(n_weeks) - 1L
  refs <- cal$isoyearweek[idx]
  mondays <- as.Date(cal$mon[idx])
  shares <- stats::dgamma(
    seq(0, max_delay_days - 1L) + 0.5,
    shape = 3,
    rate = 0.3
  )
  shares <- shares / sum(shares)

  counts <- matrix(0L, n_weeks, max_delay_days)
  fixed <- as.integer(stats::rmultinom(1, lambda, shares))
  rows <- list()
  for (k in seq_len(n_weeks)) {
    counts[k, ] <- if (identical_weeks) {
      fixed
    } else {
      as.integer(stats::rmultinom(1, stats::rpois(1, lambda), shares))
    }
    keep <- counts[k, ] > 0L
    rows[[k]] <- data.table::data.table(
      isoyearweek_reference = refs[k],
      reporting_date = mondays[k] + (seq_len(max_delay_days) - 1L)[keep],
      numerator = counts[k, keep],
      denominator = 10L * counts[k, keep],
      indicator = "test",
      location = "nation",
      age = "total",
      sex = "total"
    )
  }
  raw <- data.table::rbindlist(rows)
  as_of <- mondays[n_weeks] + observed_days
  raw <- raw[raw$reporting_date <= as_of]
  return(list(
    raw = raw[],
    refs = refs,
    mondays = mondays,
    counts = counts,
    as_of = as_of
  ))
}

sim_ecdf_tri <- function(...) {
  s <- sim_ecdf_triangle(...)
  return(csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS))
}


test_that("nowcast_delay_ecdf_v1 returns an ensemble with nowcasted draws", {
  tri <- sim_ecdf_tri()
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = 200)
  expect_s3_class(ens, "csfmt_ensemble_v3")
  expect_true("numerator_nowcasted" %in% names(ens$draws))
  expect_equal(nrow(ens$draws$numerator_nowcasted), nrow(ens$data))
  expect_equal(ncol(ens$draws$numerator_nowcasted), 200L)
  expect_true(all(ens$draws$numerator_nowcasted >= 0))
})

test_that("no nowcast draw falls below the week's observed count", {
  tri <- sim_ecdf_tri()
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = 300)
  expect_true(all(
    ens$draws$numerator_nowcasted >= ens$data$original - 1e-9
  ))
})

test_that("incomplete weeks are inflated and settled weeks stay degenerate", {
  s <- sim_ecdf_triangle()
  tri <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = 300)
  m <- ens$draws$numerator_nowcasted
  spread <- apply(m, 1, function(r) diff(range(r)))
  newest <- nrow(m)
  # the newest week has 3 of 35 delay days in, so it is completed and spread
  expect_gt(spread[newest], 0)
  expect_gt(stats::median(m[newest, ]), ens$data$original[newest])
  # the oldest week settled long ago, so it is a point mass at its observed total
  expect_equal(spread[1], 0)
  expect_equal(unname(m[1, 1]), ens$data$original[1])
})

test_that("the nowcast beats the observed count on the incomplete weeks", {
  s <- sim_ecdf_triangle()
  tri <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = 500)
  r <- ens_collapse(ens, probs = 0.5)
  truth <- rowSums(s$counts)
  age <- as.integer(s$as_of - s$mondays)
  i <- which(age >= 0L & age < 34L) # the weeks that are not settled yet
  expect_gt(length(i), 3L)
  nowcast_err <- stats::median(
    abs(r[["numerator_nowcasted_q50x0"]][i] - truth[i]) / truth[i]
  )
  observed_err <- stats::median(abs(r$original[i] - truth[i]) / truth[i])
  expect_lt(nowcast_err, observed_err)
})

test_that(".delay_ecdf pools the counts and cumulates them", {
  m <- rbind(c(1, 2, 3), c(0, 1, 1))
  expect_equal(csalert:::.delay_ecdf(m, 1:2), c(1, 4, 8) / 8)
  # non-decreasing, and exactly 1 at the last delay day
  p <- csalert:::.delay_ecdf(m, 1:2)
  expect_true(all(diff(p) >= 0))
  expect_identical(p[length(p)], 1)
  # a pool that holds no counts has no share to report
  expect_null(csalert:::.delay_ecdf(matrix(0, 2, 3), 1:2))
})

test_that(".delay_pool settles in DAYS and windows in WEEKS", {
  cal <- cstime::dates_by_isoyearweek
  i0 <- match("2022-01", cal$isoyearweek)
  refs <- cal$isoyearweek[i0 + 0:39]
  mondays <- as.Date(cal$mon[i0 + 0:39])
  as_of <- mondays[40] + 2L # the Wednesday of the newest reference week
  age <- as.integer(as_of - mondays)
  pool <- csalert:::.delay_pool(matrix(1, 40, 35), refs, as_of, 35L, 26L)

  expect_equal(pool$age_days, age)
  # settled is `age_days >= max_delay_days - 1` in DAYS, which is 34 days.
  # Read in weeks it would be 34 weeks, and the pool would be empty.
  expect_equal(which(pool$settled), which(age >= 34L))
  expect_equal(max(which(pool$settled)), 35L)
  # delay_window is WEEKS: the bound is 26 * 7 + 35 = 217 DAYS
  expect_equal(pool$train, which(age >= 34L & age < 217L))
  expect_equal(length(pool$train), 26L)
  expect_equal(length(pool$p), 35L)

  # a wider window takes every settled week; NULL takes them all as well
  wide <- csalert:::.delay_pool(matrix(1, 40, 35), refs, as_of, 35L, 100L)
  expect_equal(wide$train, which(age >= 34L))
  expect_equal(
    csalert:::.delay_pool(matrix(1, 40, 35), refs, as_of, 35L, NULL)$train,
    which(age >= 34L)
  )
})

test_that("the pooled ECDF the engine builds is an ECDF", {
  s <- sim_ecdf_triangle()
  tri <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  rts <- reporting_triangle_matrix(tri, 35L)[[1]]
  pool <- csalert:::.delay_pool(
    rts$mat,
    rts$reference,
    attr(tri, "as_of"),
    35L,
    26L
  )
  expect_equal(length(pool$train), 26L)
  expect_equal(length(pool$p), 35L)
  expect_true(all(diff(pool$p) >= 0))
  # named by the delay-day column it came from, so drop the name before the
  # identity check
  expect_identical(unname(pool$p[35]), 1)
})

test_that("the engine nowcasts a denominator column alongside", {
  tri <- sim_ecdf_tri()
  ens <- nowcast_delay_ecdf_v1(
    tri,
    max_delay_days = 35,
    n_sim = 200,
    denominator_col = "denominator"
  )
  expect_true("denominator_nowcasted" %in% names(ens$draws))
  expect_true("denominator_observed" %in% names(ens$data))
  expect_equal(nrow(ens$draws$denominator_nowcasted), nrow(ens$data))
})

test_that("the interval endpoints are pred * quantile(truth/pred, c(.05,.95))", {
  s <- sim_ecdf_triangle()
  tri <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = N_EXACT)
  r <- ens_collapse(ens, probs = c(0.05, 0.95))

  # Everything below is rebuilt from the simulated counts, not read back from
  # the engine: the pool, the ECDF, the point estimate and the ratio.
  age <- as.integer(s$as_of - s$mondays)
  settled <- age >= 34L
  train <- which(settled & age < 26L * 7L + 35L)
  expect_equal(length(train), 26L)
  p <- cumsum(colSums(s$counts[train, , drop = FALSE]))
  p <- p / p[35]

  checked <- 0L
  for (d in sort(unique(age[!settled & age >= 0L & age < 34L]))) {
    cols <- seq_len(d + 1L)
    pool_pred <- rowSums(s$counts[train, cols, drop = FALSE]) / p[d + 1L]
    rat <- rowSums(s$counts[train, , drop = FALSE]) / pool_pred
    q <- stats::quantile(rat, c(0.05, 0.95), names = FALSE)
    i <- which(age == d & !settled)
    obs <- rowSums(s$counts[i, cols, drop = FALSE])
    pred <- obs / p[d + 1L]
    expect_equal(
      r[["numerator_nowcasted_q05x0"]][i],
      pmax(pred * q[1], obs),
      info = paste("delay day", d)
    )
    expect_equal(
      r[["numerator_nowcasted_q95x0"]][i],
      pmax(pred * q[2], obs),
      info = paste("delay day", d)
    )
    checked <- checked + length(i)
  }
  expect_equal(checked, 5L) # delay days 2, 9, 16, 23 and 30
})

test_that("a pool with no spread gives an interval with no width", {
  # Every settled week carries the identical delay profile, so every
  # truth/estimate ratio is exactly 1 and the 5% and 95% quantiles coincide.
  # A parametric layer on top of the empirical endpoints would put width back.
  s <- sim_ecdf_triangle(identical_weeks = TRUE)
  tri <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = 400)
  m <- ens$draws$numerator_nowcasted
  newest <- nrow(m)
  expect_equal(diff(range(m[newest, ])), 0)
  expect_equal(max(apply(m, 1, function(r) diff(range(r)))), 0)
})

# Seeded runs ---------------------------------------------------------------

# The 2.5%, 50% and 97.5% draw quantiles, one row per reference week.
draw_q <- function(ens) {
  return(t(apply(
    ens$draws$numerator_nowcasted,
    1,
    stats::quantile,
    probs = c(0.025, 0.5, 0.975),
    names = FALSE
  )))
}

run_ecdf <- function(tri, seed = 1L, ...) {
  set.seed(seed)
  return(nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = N_EXACT, ...))
}

test_that("the defaults give the output of the code before the options", {
  # The fixture holds the output of commit 96aaae1, before the options
  # existed. data.table's .internal.selfref pointer differs between a live
  # table and a read one, so it is removed from both sides first.
  strip <- function(e) {
    attr(e$data, ".internal.selfref") <- NULL
    return(e)
  }
  ref <- readRDS(test_path("fixtures", "nowcast_delay_ecdf_defaults.rds"))
  tri <- sim_ecdf_tri()
  set.seed(20261007)
  ens <- nowcast_delay_ecdf_v1(
    tri,
    max_delay_days = 35,
    n_sim = 200,
    denominator_col = "denominator"
  )
  expect_identical(strip(ens), strip(ref))
})

test_that(".delay_pool leaves out a week with no delay information", {
  cal <- cstime::dates_by_isoyearweek
  i0 <- match("2022-01", cal$isoyearweek)
  refs <- cal$isoyearweek[i0 + 0:39]
  mondays <- as.Date(cal$mon[i0 + 0:39])
  as_of <- mondays[40] + 2L
  age <- as.integer(as_of - mondays)
  # Row 5 has counts only past the horizon, as in a bulk load. Row 6 has no
  # count at all. Both are settled.
  mat <- matrix(1, 40, 35)
  mat[5:6, ] <- 0
  late <- numeric(40)
  late[5] <- 10
  pool <- csalert:::.delay_pool(mat, refs, as_of, 35L, NULL, late)
  expect_false(5L %in% pool$train)
  expect_true(6L %in% pool$train) # a week with no count stays, as before
  expect_equal(pool$train, setdiff(which(age >= 34L), 5L))
})

# Reports past the horizon --------------------------------------------------

# The raw rows of sim_ecdf_triangle() `s`, plus one report of `n` cases at
# delay `delay` days for reference row `k`.
add_late <- function(s, k, delay = 50L, n = 777L) {
  extra <- data.table::copy(s$raw[1L])
  extra[, `:=`(
    isoyearweek_reference = s$refs[k],
    reporting_date = s$mondays[k] + delay,
    numerator = n,
    denominator = 10L * n
  )]
  return(rbind(s$raw, extra))
}

test_that("original is the count within the horizon plus the late count", {
  # Row 30 is settled and inside the pool. Its extra report at delay 50 is past
  # the horizon of 35 days.
  s <- sim_ecdf_triangle()
  tri0 <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  tri1 <- csfmt_reporting_triangle_v3(add_late(s, 30L), id_cols = ID_COLS)
  rt <- reporting_triangle_matrix(tri1, 35L)[[1]]
  expect_equal(rt$late[30], 777)
  run <- function(tri) {
    set.seed(1)
    return(nowcast_delay_ecdf_v1(
      tri,
      max_delay_days = 35,
      n_sim = 200,
      denominator_col = "denominator"
    ))
  }
  e0 <- run(tri0)
  e1 <- run(tri1)
  expect_equal(e1$data$original[30], sum(rt$mat[30, ]) + 777)
  expect_equal(
    e1$data$original - e0$data$original,
    c(rep(0, 29), 777, rep(0, 15))
  )
  expect_equal(
    e1$data$denominator_observed - e0$data$denominator_observed,
    c(rep(0, 29), 7770, rep(0, 15))
  )
  # a settled week has its observed total, late report included, in every draw
  expect_equal(unique(e1$draws$numerator_nowcasted[30, ]), e1$data$original[30])
  expect_equal(
    unique(e1$draws$denominator_nowcasted[30, ]),
    e1$data$denominator_observed[30]
  )
})

test_that("a late report in a pool week does not move the nowcast", {
  # The pool ratios T_s / O_s use the count within the horizon, so the report
  # at delay 50 in pool row 30 changes no draw of the newest week.
  s <- sim_ecdf_triangle()
  tri0 <- csfmt_reporting_triangle_v3(s$raw, id_cols = ID_COLS)
  tri1 <- csfmt_reporting_triangle_v3(add_late(s, 30L), id_cols = ID_COLS)
  d0 <- run_ecdf(tri0)$draws$numerator_nowcasted
  d1 <- run_ecdf(tri1)$draws$numerator_nowcasted
  expect_identical(d1[45, ], d0[45, ])
  expect_identical(d1[44, ], d0[44, ])
})

test_that("the reference implementation matches the engine with a late report", {
  # Pool row 30 has an extra report at delay 50, past the horizon of 35 days.
  # Both implementations keep it in original and in the draws of row 30.
  s <- sim_ecdf_triangle(lambda = 5000, observed_days = 3L)
  tri <- csfmt_reporting_triangle_v3(add_late(s, 30L), id_cols = ID_COLS)
  expect_equal(reporting_triangle_matrix(tri, 35L)[[1]]$late[30], 777)
  set.seed(1L)
  ref <- ref_nowcast_ecdf_variant(tri, 35L, n_sim = N_EXACT)
  eng <- run_ecdf(tri, delay_window = 26L)
  expect_equal(eng$data$original, ref$data$original)
  expect_equal(draw_q(eng)[30, ], draw_q(ref)[30, ])
  expect_lte(max(abs(draw_q(eng) - draw_q(ref)) / abs(draw_q(ref))), 1e-8)
})

# Two series, nation and region, of 12 reference weeks each. The as-of date is
# the Thursday of the newest week. Both series have a delivery outage on the
# Tuesday to Thursday of weeks 5 and 6. In the nation series, weeks 1 to 3 have
# one report each, on the as-of date. That is past the horizon, as in a bulk
# load. `drop_bulk = TRUE` removes those 3 weeks from the triangle.
sim_bulk_tri <- function(drop_bulk = FALSE) {
  s <- sim_ecdf_triangle(n_weeks = 12L, lambda = 5000, observed_days = 3L)
  raw <- rbind(
    s$raw,
    data.table::copy(s$raw)[, location := "region"]
  )
  for (k in 5:6) {
    gap <- s$mondays[k] + 1:3
    raw[reporting_date %in% gap, reporting_date := s$mondays[k] + 4L]
  }
  old <- raw$location == "nation" & raw$isoyearweek_reference %in% s$refs[1:3]
  bulk <- raw[
    old,
    .(numerator = sum(numerator), denominator = sum(denominator)),
    by = .(isoyearweek_reference, indicator, location, age, sex)
  ]
  bulk[, reporting_date := s$as_of]
  raw <- raw[!old]
  if (!drop_bulk) {
    raw <- rbind(raw, bulk, use.names = TRUE)
  }
  raw <- raw[,
    .(numerator = sum(numerator), denominator = sum(denominator)),
    by = .(isoyearweek_reference, reporting_date, indicator, location, age, sex)
  ]
  return(list(
    tri = csfmt_reporting_triangle_v3(raw, id_cols = ID_COLS),
    bulk = bulk,
    refs = s$refs
  ))
}

test_that("a bulk-loaded week stays out of the pool, and in the output", {
  with_bulk <- sim_bulk_tri()
  without <- sim_bulk_tri(drop_bulk = TRUE)
  rt <- reporting_triangle_matrix(with_bulk$tri, 35L)
  tri <- with_bulk$tri
  nat <- unique(tri$time_series_id[tri$location == "nation"])
  expect_length(nat, 1L)
  bulk_rows <- match(with_bulk$refs[1:3], rt[[nat]]$reference)
  expect_equal(unname(rowSums(rt[[nat]]$mat[bulk_rows, ])), rep(0, 3))
  expect_true(all(rt[[nat]]$late[bulk_rows] > 0))

  # The sorted draws of the two newest nation weeks. Sorting makes the
  # comparison independent of the order in which the weeks use random numbers.
  newest <- function(ens) {
    keep <- ens$data$location == "nation" &
      ens$data$isoyearweek %in% with_bulk$refs[11:12]
    m <- ens$draws$numerator_nowcasted[keep, , drop = FALSE]
    return(t(apply(m, 1, sort)))
  }
  a <- run_ecdf(with_bulk$tri)
  b <- run_ecdf(without$tri)
  expect_equal(newest(a), newest(b), tolerance = 1e-12)
  # the newest weeks are nowcast, not left at their observed count
  expect_true(all(apply(newest(a), 1, function(r) diff(range(r)) > 0)))
  # the bulk-loaded weeks keep their count in original and in every draw
  keep <- a$data$location == "nation" &
    a$data$isoyearweek %in% with_bulk$refs[1:3]
  expect_equal(a$data$original[keep], with_bulk$bulk$numerator)
  expect_equal(
    unname(a$draws$numerator_nowcasted[keep, 1]),
    with_bulk$bulk$numerator
  )
})

test_that("a removed argument errors instead of being ignored", {
  tri <- sim_ecdf_tri()
  expect_error(
    nowcast_delay_ecdf_v1(tri, max_delay_days = 35, interval = "log_robust"),
    "unused argument(s): interval",
    fixed = TRUE
  )
  expect_error(
    nowcast_delay_ecdf_v1(tri, max_delay_days = 35, outage_gap_days = 3),
    "unused argument(s): outage_gap_days",
    fixed = TRUE
  )
})
