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

# The interval and outage_gap_days options --------------------------------

# A triangle with a delivery outage in each week of `outage_weeks`: nothing
# arrives on its Tuesday, Wednesday or Thursday, and those counts arrive on its
# Friday as a backlog. The as-of date is the Thursday of the newest week, so the
# newest week is observed for delay days 0 to 3.
sim_outage_tri <- function(outage_weeks, n_weeks = 45L, lambda = 5000) {
  s <- sim_ecdf_triangle(n_weeks = n_weeks, lambda = lambda, observed_days = 3L)
  raw <- data.table::copy(s$raw)
  for (k in outage_weeks) {
    gap <- s$mondays[k] + 1:3
    raw[reporting_date %in% gap, reporting_date := s$mondays[k] + 4L]
  }
  raw <- raw[,
    .(numerator = sum(numerator), denominator = sum(denominator)),
    by = .(isoyearweek_reference, reporting_date, indicator, location, age, sex)
  ]
  return(csfmt_reporting_triangle_v3(raw, id_cols = ID_COLS))
}

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

# Fixture (b) and (c): pool week 35 and week 44 have an outage. Week 45 is the
# newest, at delay day 3, and week 44 is at delay day 10.
OUTAGE_POOL_WEEK <- 35L

run_ecdf <- function(tri, seed = 1L, ...) {
  set.seed(seed)
  return(nowcast_delay_ecdf_v1(tri, max_delay_days = 35, n_sim = N_EXACT, ...))
}

test_that("(a) the defaults give the output of the code before the options", {
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
  set.seed(20261007)
  ens2 <- nowcast_delay_ecdf_v1(
    tri,
    max_delay_days = 35,
    n_sim = 200,
    denominator_col = "denominator",
    interval = "empirical",
    outage_gap_days = NULL
  )
  expect_identical(strip(ens2), strip(ref))
})

test_that("(b) outage_gap_days drops an outage pool week from the limit", {
  tri <- sim_outage_tri(c(OUTAGE_POOL_WEEK, 44L))
  m <- reporting_triangle_matrix(tri, 35L)[[1]]
  age <- as.integer(
    attr(tri, "as_of") - csalert:::isoyearweek_week_start(m$reference)
  )
  train <- which(age >= 34L & age < 26L * 7L + 35L)
  expect_true(OUTAGE_POOL_WEEK %in% train)
  ratio <- rowSums(m$mat[train, ]) / rowSums(m$mat[train, 1:4])
  # the outage week has the largest pool ratio by far
  expect_identical(train[which.max(ratio)], OUTAGE_POOL_WEEK)
  newest <- nrow(m$mat)
  ceiling_clean <- sum(m$mat[newest, 1:4]) *
    max(ratio[train != OUTAGE_POOL_WEEK])

  q_plain <- draw_q(run_ecdf(tri))[newest, 3]
  q_drop <- draw_q(run_ecdf(tri, outage_gap_days = 3))[newest, 3]
  # without the option the outage ratio sets the 97.5% limit
  expect_gt(q_plain, 10 * ceiling_clean)
  # with it, the limit sits inside the range the other pool weeks give
  expect_lte(q_drop, ceiling_clean)
})

test_that("(c) a target week with its own outage keeps the outage pool weeks", {
  tri <- sim_outage_tri(c(OUTAGE_POOL_WEEK, 44L))
  plain <- run_ecdf(tri)$draws$numerator_nowcasted
  drop <- run_ecdf(tri, outage_gap_days = 3)$draws$numerator_nowcasted
  # week 44 has an outage in its delay days 0 to 10, so its pool is the full pool
  expect_equal(sort(drop[44, ]), sort(plain[44, ]), tolerance = 1e-12)
  # the newest week has none, so its pool changes
  expect_false(isTRUE(all.equal(sort(drop[45, ]), sort(plain[45, ]))))
})

test_that("(d) the full pool stays when fewer than 3 clean pool weeks remain", {
  # delay_window = 4 gives a pool of 4 weeks, rows 37 to 40
  one <- sim_outage_tri(38L)
  two <- sim_outage_tri(c(38L, 39L))
  newest <- 45L
  # 1 outage week: 3 pool weeks remain, so the outage week is dropped
  expect_false(isTRUE(all.equal(
    draw_q(run_ecdf(one, delay_window = 4, outage_gap_days = 3))[newest, ],
    draw_q(run_ecdf(one, delay_window = 4))[newest, ]
  )))
  # 2 outage weeks: 2 pool weeks remain, so the full pool is used
  expect_equal(
    draw_q(run_ecdf(two, delay_window = 4, outage_gap_days = 3))[newest, ],
    draw_q(run_ecdf(two, delay_window = 4))[newest, ],
    tolerance = 1e-12
  )
})

test_that("(e) log_robust: one extreme pool ratio does not set the limit", {
  tri <- sim_outage_tri(c(OUTAGE_POOL_WEEK, 44L))
  m <- reporting_triangle_matrix(tri, 35L)[[1]]
  age <- as.integer(
    attr(tri, "as_of") - csalert:::isoyearweek_week_start(m$reference)
  )
  train <- which(age >= 34L & age < 26L * 7L + 35L)
  ratio <- rowSums(m$mat[train, ]) / rowSums(m$mat[train, 1:4])
  newest <- nrow(m$mat)
  ceiling_clean <- sum(m$mat[newest, 1:4]) *
    max(ratio[train != OUTAGE_POOL_WEEK])
  q_emp <- draw_q(run_ecdf(tri))[newest, 3]
  q_rob <- draw_q(run_ecdf(tri, interval = "log_robust"))[newest, 3]
  expect_gt(q_emp, 10 * ceiling_clean)
  expect_lte(q_rob, ceiling_clean)
  expect_error(run_ecdf(tri, interval = "nonsense"))
  expect_error(run_ecdf(tri, outage_gap_days = 0), "outage_gap_days")
})

test_that("(f) the options match the reference implementation", {
  rel_err <- function(a, b) {
    qa <- draw_q(a)
    qb <- draw_q(b)
    return(max(abs(qa - qb) / abs(qb)))
  }
  fixtures <- list(
    b_c = list(tri = sim_outage_tri(c(OUTAGE_POOL_WEEK, 44L)), window = 26L),
    d_drop = list(tri = sim_outage_tri(38L), window = 4L),
    d_fallback = list(tri = sim_outage_tri(c(38L, 39L)), window = 4L)
  )
  for (nm in names(fixtures)) {
    tri <- fixtures[[nm]]$tri
    w <- fixtures[[nm]]$window
    ref <- function(...) {
      set.seed(1L)
      return(ref_nowcast_ecdf_variant(
        tri,
        35L,
        delay_window = w,
        n_sim = N_EXACT,
        ...
      ))
    }
    expect_lte(
      rel_err(
        run_ecdf(tri, delay_window = w, outage_gap_days = 3),
        ref(drop_outages = TRUE, gap_days = 3)
      ),
      1e-8,
      label = paste(nm, "outage_gap_days = 3")
    )
    expect_lte(
      rel_err(
        run_ecdf(tri, delay_window = w, interval = "log_robust"),
        ref(robust = TRUE)
      ),
      1e-8,
      label = paste(nm, "log_robust")
    )
    expect_lte(
      rel_err(
        run_ecdf(
          tri,
          delay_window = w,
          interval = "log_robust",
          outage_gap_days = 3
        ),
        ref(robust = TRUE, drop_outages = TRUE, gap_days = 3)
      ),
      1e-8,
      label = paste(nm, "log_robust and outage_gap_days = 3")
    )
  }
})
