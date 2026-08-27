# Batched trend on the ensemble: kernel correctness + seam-safety.

test_that("rolling_slope_matrix is bit-identical to per-column OLS", {
  set.seed(1)
  Y <- matrix(stats::rpois(20 * 4, 30), nrow = 20)
  width <- 3
  rs <- rolling_slope_matrix(Y, width)

  ref <- matrix(NA_real_, 20, 4)
  for (j in 1:4) {
    for (i in width:20) {
      yy <- Y[(i - width + 1):i, j]
      tt <- seq_len(width)
      ref[i, j] <- stats::coef(stats::lm(yy ~ tt))[[2]]
    }
  }
  expect_equal(rs$beta1[width:20, ], ref[width:20, ], tolerance = 1e-9)
  expect_true(all(is.na(rs$beta1[1:(width - 1), ])))
})

test_that("short_term_trend.csfmt_ensemble_v3 adds seam-masked gr/beta1 draws", {
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = wk
  )
  n <- nrow(d)
  M <- matrix(rep(seq_len(n) * 5, 6), nrow = n) # increasing level, 6 draws
  ens <- csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = M)
  )

  out <- short_term_trend(ens, measure = "cases", trend_isoyearweeks = 3)
  expect_true("cases_trend_gr" %in% names(out$draws))
  expect_true("cases_trend_beta1" %in% names(out$draws))

  gr <- out$draws[["cases_trend_gr"]]
  expect_true(all(is.na(gr[1:2, ]))) # leading width-1 rows masked
  expect_true(all(gr[3:n, ] > 0)) # increasing -> positive growth

  # P(increasing) emitted as a point column; 1 for a monotone increasing series
  expect_true("cases_trend_increasing_pr" %in% names(out$data))
  expect_equal(out$data$cases_trend_increasing_pr[3:n], rep(1, n - 2))
})

test_that("stacked series do not contaminate across the seam", {
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  n1 <- length(wk)
  d <- rbind(
    data.table::data.table(
      indicator = "flu",
      location = "nation",
      age = "total",
      isoyearweek = wk
    ),
    data.table::data.table(
      indicator = "rsv",
      location = "nation",
      age = "total",
      isoyearweek = wk
    )
  )
  M <- matrix(c(seq_len(n1) * 5, seq_len(n1) * 5), ncol = 1) # two ramps stacked, 1 draw
  ens <- csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = M)
  )

  out <- short_term_trend(ens, measure = "cases", trend_isoyearweeks = 3)
  beta1 <- out$draws[["cases_trend_beta1"]]
  iid <- out$data$time_series_internal_id

  expect_true(all(is.na(beta1[iid < 3, ]))) # boundary-crossing windows masked
  expect_true(all(beta1[iid >= 3, ] > 0)) # each series' clean ramp slope, no contamination
})

test_that("missing measure errors", {
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = c("2020-01", "2020-02", "2020-03")
  )
  ens <- csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = matrix(1:9, 3))
  )
  expect_error(short_term_trend(ens, measure = "nope"), "not in")
})

test_that("a single-draw ensemble still gets a real P(increasing)", {
  # This is the passthrough case: nowcast_passthrough_to_ensemble_v1 emits one
  # draw. The level is then certain, but the LINE fitted through it is not, so
  # the slope's own sampling error still has to reach the draws. Before that
  # was mandatory, this case collapsed to a bare sign test on a 3-point slope
  # and P(increasing) was exactly 0 or 1.
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = wk
  )
  n <- nrow(d)
  set.seed(4)
  M <- matrix(stats::rpois(n, 40), ncol = 1) # ONE draw, as passthrough gives
  ens <- csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = M)
  )

  set.seed(11)
  out <- short_term_trend(
    ens,
    measure = "cases",
    trend_isoyearweeks = 5,
    n_sim = 1000L
  )
  # the trend's own draw axis widened to n_sim, though the measure kept one draw
  expect_equal(ncol(out$draws[["cases_trend_gr"]]), 1000L)
  expect_equal(ncol(out$draws[["cases"]]), 1L)
  inc <- out$data$cases_trend_increasing_pr[5:n]
  expect_true(any(inc > 0 & inc < 1))
})

test_that("`propagate_slope_error` is refused rather than silently ignored", {
  # It was removed. The method takes `...`, so without an explicit guard a
  # caller who had turned it off would get propagated numbers and no notice.
  wk <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = wk
  )
  M <- matrix(stats::rpois(nrow(d), 40), ncol = 1)
  ens <- csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = M)
  )
  for (v in c(TRUE, FALSE)) {
    expect_error(
      short_term_trend(
        ens,
        measure = "cases",
        trend_isoyearweeks = 5,
        propagate_slope_error = v
      ),
      "was removed"
    )
  }
})

# ---- link-scale families: the estimand the older GLM pipeline reports --------
#
# The pipeline these numbers must line up with fits a quasi-Poisson log-link
# model for counts, and glm(f ~ 1 + week, weights = T, family = binomial) for
# fractions. Both report coef(model)[2], a slope on the link scale. The
# reference below refits every window with stats::glm, which is the per-window
# loop the batched kernel exists to replace.

ref_glm <- function(
  y,
  width,
  family,
  denom = NULL,
  control = stats::glm.control()
) {
  b <- se <- rep(NA_real_, length(y))
  for (i in width:length(y)) {
    idx <- (i - width + 1):i
    dd <- data.frame(week = seq_len(width), y = y[idx])
    if (family == "binomial") {
      dd$tot <- denom[idx]
      m <- stats::glm(
        y ~ week,
        data = dd,
        weights = tot,
        family = stats::binomial,
        control = control
      )
    } else {
      m <- stats::glm(
        y ~ week,
        data = dd,
        family = stats::quasipoisson,
        control = control
      )
    }
    b[i] <- stats::coef(m)[[2]]
    se[i] <- summary(m)$coefficients[2, 2]
  }
  list(beta1 = b, se = se)
}

ens_1draw <- function(y, denom = NULL) {
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = sprintf("2020-%02d", seq_along(y))
  )
  dr <- list(cases = matrix(y, ncol = 1))
  if (!is.null(denom)) {
    dr$tested <- matrix(denom, ncol = 1)
  }
  csfmt_ensemble_v3(d, id_cols = c("indicator", "location", "age"), draws = dr)
}

# short_term_trend() writes its P(increasing) into $data by reference, so a
# fixture reused across two calls carries the first call's column into the
# second. Every test below builds its ensemble fresh.
ens_2draw <- function() {
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = sprintf("2020-%02d", 1:8)
  )
  Y <- cbind(c(0, 3, 2, 5, 4, 9, 8, 14), c(2, 2, 6, 5, 3, 7, 11, 10))
  csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = Y)
  )
}

test_that("family = 'identity' reproduces the pre-change kernel exactly", {
  # Captured from csalert 2026.8.23 (commit ed0749b), before `family` existed.
  # Any drift in the default path lands here.
  #
  # These read `rolling_slope_matrix()`, not `short_term_trend()`. The method
  # always perturbs the slope now, so `$draws[["cases_trend_beta1"]]` holds the
  # perturbed draws rather than the point estimate. The kernel is what the
  # pre-change literals describe, and it is unchanged.
  Y <- cbind(c(0, 3, 2, 5, 4, 9, 8, 14), c(2, 2, 6, 5, 3, 7, 11, 10))
  rs <- rolling_slope_matrix(Y, 3)
  expect_identical(
    rs$beta1,
    structure(
      c(NA, NA, 1, 1, 1, 2, 2, 2.5, NA, NA, 2, 1.5, -1.5, 1, 4, 1.5),
      dim = c(8L, 2L)
    )
  )
  expect_identical(
    100 * rs$beta1 / Y,
    structure(
      c(
        NA,
        NA,
        50,
        20,
        25,
        22.222222222222221,
        25,
        17.857142857142858,
        NA,
        NA,
        33.333333333333336,
        30,
        -50,
        14.285714285714286,
        36.363636363636367,
        15
      ),
      dim = c(8L, 2L)
    )
  )
  expect_identical(
    rowMeans(rs$beta1 > 0, na.rm = TRUE),
    c(NaN, NaN, 1, 1, 0.5, 1, 1, 1)
  )

  set.seed(42)
  b <- short_term_trend(
    ens_2draw(),
    measure = "cases",
    trend_isoyearweeks = 4
  )
  expect_identical(
    b$draws[["cases_trend_beta1"]],
    structure(
      c(
        NA,
        NA,
        NA,
        1.3688011088497558,
        0.5739055785006959,
        3.1592022709773007,
        2.1890924558187468,
        5.9044372443274069,
        NA,
        NA,
        NA,
        1.5818796079510054,
        2.7449311104075131,
        -3.8111627475642775,
        1.7348461261144796,
        0.42313321191191688
      ),
      dim = c(8L, 2L)
    )
  )
  expect_identical(
    b$draws[["cases_trend_gr"]],
    structure(
      c(
        NA,
        NA,
        NA,
        27.376022176995114,
        14.347639462517398,
        35.102247455303342,
        27.363655697734334,
        42.174551745195764,
        NA,
        NA,
        NA,
        31.637592159020109,
        91.497703680250439,
        -54.445182108061104,
        15.771328419222543,
        4.2313321191191688
      ),
      dim = c(8L, 2L)
    )
  )
  expect_identical(
    b$data[["cases_trend_increasing_pr"]],
    c(NA, NA, NA, 1, 1, 0.5, 1, 1)
  )
})

test_that("family = 'quasipoisson' matches a per-window glm, zeros included", {
  # `tight` runs stats::glm past its own epsilon = 1e-8 stop. Without it the
  # comparison measures glm's convergence slack, which reaches 3.2e-6 on the
  # standard error, rather than the kernel.
  tight <- stats::glm.control(epsilon = 1e-12, maxit = 100)
  for (y in list(
    c(4, 6, 5, 9, 11, 10, 14, 19, 17, 26, 31, 29),
    c(0, 1, 0, 2, 0, 3, 5, 4, 0, 9, 12, 11)
  )) {
    # the kernel, not the method: short_term_trend() always perturbs the slope
    # by its own standard error, so $draws holds the perturbed draws.
    rs <- rolling_slope_matrix(matrix(y, ncol = 1), 4, family = "quasipoisson")
    ref <- ref_glm(y, 4, "quasipoisson")
    expect_equal(rs$beta1[, 1], ref$beta1, tolerance = 1e-6)
    expect_equal(
      100 * (exp(rs$beta1[, 1]) - 1),
      100 * (exp(ref$beta1) - 1),
      tolerance = 1e-6
    )
    expect_equal(
      rolling_slope_matrix(matrix(y, ncol = 1), 4, family = "quasipoisson")$se[,
        1
      ],
      ref_glm(y, 4, "quasipoisson", control = tight)$se,
      tolerance = 1e-6
    )
  }
})

test_that("family = 'binomial' matches a per-window weighted glm", {
  tight <- stats::glm.control(epsilon = 1e-12, maxit = 100)
  n_pos <- c(2, 5, 4, 9, 8, 14, 16, 21, 24, 30, 33, 40)
  n_tot <- c(50, 55, 48, 60, 52, 61, 58, 66, 63, 70, 68, 75)
  f <- n_pos / n_tot
  # the kernel, not the method: short_term_trend() always perturbs the slope
  # by its own standard error, so $draws holds the perturbed draws.
  rs <- rolling_slope_matrix(
    matrix(f, ncol = 1),
    4,
    family = "binomial",
    prior_weights = matrix(n_tot, ncol = 1)
  )
  ref <- ref_glm(f, 4, "binomial", denom = n_tot)
  expect_equal(rs$beta1[, 1], ref$beta1, tolerance = 1e-6)
  expect_equal(
    100 * (exp(rs$beta1[, 1]) - 1),
    100 * (exp(ref$beta1) - 1),
    tolerance = 1e-6
  )
  expect_equal(
    rolling_slope_matrix(
      matrix(f, ncol = 1),
      4,
      family = "binomial",
      prior_weights = matrix(n_tot, ncol = 1)
    )$se[, 1],
    ref_glm(f, 4, "binomial", denom = n_tot, control = tight)$se,
    tolerance = 1e-6
  )
})

test_that("P(increasing) is never degenerate at width 3", {
  # Every 3-week window here zig-zags, so the slope is small next to its own
  # standard error: max |beta1 / se| is 0.43. Without the slope's error every
  # one of these would read as certainty, 0 or 1. A GLM Wald interval is
  # asymptotic, so the perturbation is normal and width 3 stays usable.
  y <- c(10, 13, 11, 14, 12, 15, 13, 16, 14, 17, 12, 16)

  set.seed(7)
  on <- short_term_trend(
    ens_1draw(y),
    measure = "cases",
    trend_isoyearweeks = 3,
    family = "quasipoisson"
  )
  inc_on <- on$data[["cases_trend_increasing_pr"]][3:length(y)]
  expect_true(all(inc_on > 0 & inc_on < 1))
  expect_equal(ncol(on$draws[["cases_trend_beta1"]]), 1000L)

  # the point slope itself is not degenerate-free by luck: read straight off
  # the kernel, every one of these windows has a definite sign
  rs <- rolling_slope_matrix(matrix(y, ncol = 1), 3, family = "quasipoisson")
  expect_true(all(rs$beta1[3:length(y), 1] != 0))
})

# The two GLM families do not share a reference distribution, because they do
# not share a dispersion. Quasi-Poisson estimates one from width - 2 residual
# degrees of freedom, which is the case summary.glm() refers to a t. The
# binomial family fixes it at 1, so a normal is right there.
ens_2draw_binom <- function() {
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    isoyearweek = sprintf("2020-%02d", 1:8)
  )
  P <- cbind(
    c(0.04, 0.09, 0.08, 0.15, 0.13, 0.23, 0.21, 0.32),
    c(0.05, 0.06, 0.11, 0.13, 0.09, 0.18, 0.26, 0.28)
  )
  N <- cbind(rep(50, 8), rep(70, 8))
  csfmt_ensemble_v3(
    d,
    id_cols = c("indicator", "location", "age"),
    draws = list(cases = P, tested = N)
  )
}

test_that("error_reference = 'auto' gives quasipoisson a t and binomial a normal", {
  # A strictly interior P(increasing) does not pin the reference. A t and a
  # normal both give one. So recompute the RNG stream here: that pins the
  # distribution, its degrees of freedom and the number of variates. The
  # `.Random.seed` assertion pins the count, because nothing else in the call
  # draws.
  seed <- 20260821L
  width <- 4

  # Two draws in, so the n_sim widening never fires and `beta1` keeps its shape.
  rs <- rolling_slope_matrix(
    ens_2draw()$draws[["cases"]],
    width,
    family = "quasipoisson"
  )
  set.seed(seed)
  err <- stats::rt(length(rs$beta1), df = width - 2)
  want <- rs$beta1 + rs$se * matrix(err, nrow(rs$beta1), ncol(rs$beta1))
  state <- get(".Random.seed", envir = globalenv())

  set.seed(seed)
  out <- short_term_trend(
    ens_2draw(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "quasipoisson"
  )
  expect_identical(out$draws[["cases_trend_beta1"]], want)
  expect_identical(get(".Random.seed", envir = globalenv()), state)

  eb <- ens_2draw_binom()
  rsb <- rolling_slope_matrix(
    eb$draws[["cases"]],
    width,
    family = "binomial",
    prior_weights = eb$draws[["tested"]]
  )
  set.seed(seed)
  errb <- stats::rnorm(length(rsb$beta1))
  wantb <- rsb$beta1 + rsb$se * matrix(errb, nrow(rsb$beta1), ncol(rsb$beta1))
  stateb <- get(".Random.seed", envir = globalenv())

  set.seed(seed)
  outb <- short_term_trend(
    ens_2draw_binom(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "binomial",
    denominator = "tested"
  )
  expect_identical(outb$draws[["cases_trend_beta1"]], wantb)
  expect_identical(get(".Random.seed", envir = globalenv()), stateb)
})

test_that("error_reference = 'normal' overrides the auto t for quasipoisson", {
  # The consumer of the log link matches an older pipeline whose interval comes
  # from confint(), which profiles the deviance against an asymptotic
  # chi-squared. That is a normal reference, not a t. The override exists for
  # exactly that case, so it has to reach the draw.
  seed <- 20260821L
  width <- 4

  rs <- rolling_slope_matrix(
    ens_2draw()$draws[["cases"]],
    width,
    family = "quasipoisson"
  )
  set.seed(seed)
  err <- stats::rnorm(length(rs$beta1))
  want <- rs$beta1 + rs$se * matrix(err, nrow(rs$beta1), ncol(rs$beta1))

  set.seed(seed)
  out <- short_term_trend(
    ens_2draw(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "quasipoisson",
    error_reference = "normal"
  )
  expect_identical(out$draws[["cases_trend_beta1"]], want)

  # and "auto" really does differ on this fixture, so the override is not a
  # no-op that would pass whatever the argument did
  set.seed(seed)
  auto <- short_term_trend(
    ens_2draw(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "quasipoisson"
  )
  expect_false(identical(auto$draws[["cases_trend_beta1"]], want))
})

test_that("a separated window returns NA and warns once with the count", {
  # Four zero weeks then a rise. This is ordinary early-season surveillance
  # data. The window at rows 2:5 quasi-separates, so the logit slope has no
  # finite solution and IRLS runs to maxit. Before the convergence gate its
  # last iterate reached $draws as a growth rate of 1.06e13 percent per week.
  # That number is finite, so no is.finite() filter could remove it.
  f <- c(0, 0, 0, 0, 0.2, 0.3, 0.4, 0.5)
  n_tot <- rep(50, length(f))

  expect_warning(
    out <- short_term_trend(
      ens_1draw(f, n_tot),
      measure = "cases",
      trend_isoyearweeks = 4,
      family = "binomial",
      denominator = "tested"
    ),
    "did not converge in 2 of 5 window fits"
  )
  b <- out$draws[["cases_trend_beta1"]][, 1]
  g <- out$draws[["cases_trend_gr"]][, 1]
  # rows 1:3 hold no complete window; rows 4 and 5 hold the separated ones
  expect_true(all(is.na(b[1:5])))
  expect_true(all(is.na(g[1:5])))
  expect_false(anyNA(b[6:8]))
  expect_true(all(g[6:8] > 0))
  expect_equal(
    out$data[["cases_trend_increasing_pr"]][4:5],
    c(NA_real_, NA_real_)
  )

  # the kernel names the same two windows through `converged`
  rs <- suppressWarnings(rolling_slope_matrix(
    matrix(f, ncol = 1),
    4,
    family = "binomial",
    prior_weights = matrix(n_tot, ncol = 1)
  ))
  expect_identical(
    rs$converged[, 1],
    c(NA, NA, NA, FALSE, FALSE, TRUE, TRUE, TRUE)
  )
  expect_true(all(is.na(rs$se[4:5, 1])))

  # quasi-Poisson separates on the same window and gets the same treatment
  expect_warning(
    outq <- short_term_trend(
      ens_1draw(f),
      measure = "cases",
      trend_isoyearweeks = 4,
      family = "quasipoisson"
    ),
    "did not converge in 2 of 5 window fits"
  )
  expect_true(all(is.na(outq$draws[["cases_trend_beta1"]][4:5, 1])))
  expect_false(anyNA(outq$draws[["cases_trend_beta1"]][6:8, 1]))
})

test_that("the binomial denominator is required, and the others reject it", {
  y <- c(0.1, 0.2, 0.15, 0.3, 0.25)
  expect_error(
    short_term_trend(
      ens_1draw(y, rep(50, 5)),
      measure = "cases",
      family = "binomial"
    ),
    "needs `denominator`"
  )
  expect_error(
    short_term_trend(
      ens_1draw(y, rep(50, 5)),
      measure = "cases",
      family = "binomial",
      denominator = "nope"
    ),
    "not in"
  )
  expect_error(
    short_term_trend(
      ens_1draw(y, rep(50, 5)),
      measure = "cases",
      denominator = "tested"
    ),
    "only used by family"
  )
  expect_error(
    rolling_slope_matrix(
      matrix(y, ncol = 1),
      3,
      family = "quasipoisson",
      prior_weights = matrix(1, 5, 1)
    ),
    "only used by family"
  )
})

test_that("a positional call binds trend_isoyearweeks then n_sim", {
  # Removing `propagate_slope_error` moved `n_sim` from argument 5 to argument
  # 4. Argument 3 is still `trend_isoyearweeks`. Two signals pin that: width 3
  # leaves exactly two leading NA rows, and `n_sim` sets the draw-axis width of
  # a single-draw ensemble. 250 is not the 1000 default, so a positional slip
  # cannot pass by accident.
  y <- c(4, 6, 5, 9, 11, 10, 14, 19, 17, 26, 31, 29)

  set.seed(3)
  pos <- short_term_trend(ens_1draw(y), "cases", 3, 250L)
  set.seed(3)
  named <- short_term_trend(
    ens_1draw(y),
    measure = "cases",
    trend_isoyearweeks = 3,
    n_sim = 250L
  )
  expect_identical(
    pos$draws[["cases_trend_beta1"]],
    named$draws[["cases_trend_beta1"]]
  )

  b <- pos$draws[["cases_trend_beta1"]]
  expect_true(all(is.na(b[1:2, ]))) # width 3, so two leading rows and no more
  expect_false(anyNA(b[3, ]))
  expect_identical(ncol(b), 250L) # argument 4 reached n_sim
})

test_that("a separated window also masks beta0", {
  # `beta0` used to keep its last unsuccessful iterate beside `converged =
  # FALSE` and an NA slope. A direct rolling_slope_matrix() caller then read it
  # as a fitted intercept. The two separated windows below held -27.3 and
  # -100.1 on the logit scale.
  f <- c(0, 0, 0, 0, 0.2, 0.3, 0.4, 0.5)
  n_tot <- rep(50, length(f))
  rs <- suppressWarnings(rolling_slope_matrix(
    matrix(f, ncol = 1),
    4,
    family = "binomial",
    prior_weights = matrix(n_tot, ncol = 1)
  ))
  expect_true(all(is.na(rs$beta0[4:5, 1])))
  expect_false(anyNA(rs$beta0[6:8, 1])) # the converged windows keep theirs
})

test_that("width 2 is refused wherever the dispersion is estimated", {
  # Identity and quasi-Poisson both read a dispersion off width - 2 residual
  # degrees of freedom. At width 2 there are none, so `se` has no value and no
  # `error_reference` repairs it. The binomial family fixes the dispersion at 1.
  y <- c(4, 6, 5, 9, 11, 10)
  f <- c(0.1, 0.2, 0.15, 0.3, 0.25, 0.35)
  n_tot <- rep(50, length(f))

  for (fam in c("identity", "quasipoisson")) {
    for (er in c("auto", "normal", "t")) {
      expect_error(
        short_term_trend(
          ens_1draw(y),
          measure = "cases",
          trend_isoyearweeks = 2,
          family = fam,
          error_reference = er
        ),
        sprintf("trend_isoyearweeks >= 3 under family = '%s'", fam)
      )
    }
  }

  # the reason for the floor: at width 2 `se` is NaN under identity and Inf
  # under quasi-Poisson, and finite under binomial
  expect_true(all(is.nan(
    rolling_slope_matrix(matrix(y, ncol = 1), 2)$se[2:6, 1]
  )))
  expect_true(all(is.infinite(
    rolling_slope_matrix(matrix(y, ncol = 1), 2, family = "quasipoisson")$se[
      2:6,
      1
    ]
  )))
  expect_false(anyNA(
    rolling_slope_matrix(
      matrix(f, ncol = 1),
      2,
      family = "binomial",
      prior_weights = matrix(n_tot, ncol = 1)
    )$se[2:6, 1]
  ))

  # binomial at width 2 runs, and every growth rate is a real number
  set.seed(5)
  ok <- short_term_trend(
    ens_1draw(f, n_tot),
    measure = "cases",
    trend_isoyearweeks = 2,
    family = "binomial",
    denominator = "tested"
  )
  gr <- ok$draws[["cases_trend_gr"]]
  expect_identical(ncol(gr), 1000L)
  expect_false(anyNA(gr[2:length(f), ]))

  # a t reference still needs 1 degree of freedom, on every family
  expect_error(
    short_term_trend(
      ens_1draw(f, n_tot),
      measure = "cases",
      trend_isoyearweeks = 2,
      family = "binomial",
      denominator = "tested",
      error_reference = "t"
    ),
    "error_reference = 't'"
  )
})

test_that("error_reference = 't' overrides the auto normal for binomial", {
  # "auto" gives the binomial family a normal, so an explicit "t" is the only
  # route to a t there. Recompute the RNG stream: that pins the distribution,
  # its degrees of freedom and the number of variates.
  seed <- 20260821L
  width <- 4

  eb <- ens_2draw_binom()
  rs <- rolling_slope_matrix(
    eb$draws[["cases"]],
    width,
    family = "binomial",
    prior_weights = eb$draws[["tested"]]
  )
  set.seed(seed)
  err <- stats::rt(length(rs$beta1), df = width - 2)
  want <- rs$beta1 + rs$se * matrix(err, nrow(rs$beta1), ncol(rs$beta1))
  state <- get(".Random.seed", envir = globalenv())

  set.seed(seed)
  out <- short_term_trend(
    ens_2draw_binom(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "binomial",
    denominator = "tested",
    error_reference = "t"
  )
  expect_identical(out$draws[["cases_trend_beta1"]], want)
  expect_identical(get(".Random.seed", envir = globalenv()), state)

  # and "auto" really does differ on this fixture, so the override is not a
  # no-op that would pass whatever the argument did
  set.seed(seed)
  auto <- short_term_trend(
    ens_2draw_binom(),
    measure = "cases",
    trend_isoyearweeks = width,
    family = "binomial",
    denominator = "tested"
  )
  expect_false(identical(auto$draws[["cases_trend_beta1"]], want))
})

test_that("an all-zero window returns NA where stats::glm() returns a slope of 0", {
  # A deliberate divergence, and the only one. stats::glm() stops on the
  # relative change in the deviance, which is 0 for an all-zero window from the
  # first iteration. The kernel stops on the coefficient step, and that step
  # never settles: the intercept marches to -Inf as the fitted mean goes to 0.
  # An all-zero window identifies no slope. An early-season surveillance series
  # holds them, so this decision is visible rather than incidental.
  z <- matrix(rep(0, 4), ncol = 1)
  expect_warning(
    rs <- rolling_slope_matrix(z, 4, family = "quasipoisson"),
    "did not converge in 1 of 1 window fits"
  )
  expect_identical(rs$converged[, 1], c(NA, NA, NA, FALSE))
  expect_identical(rs$beta0[, 1], rep(NA_real_, 4))
  expect_identical(rs$beta1[, 1], rep(NA_real_, 4))
  expect_identical(rs$se[, 1], rep(NA_real_, 4))

  # what stats::glm() answers on the same window
  m <- stats::glm(
    y ~ week,
    data = data.frame(week = 1:4, y = rep(0, 4)),
    family = stats::quasipoisson
  )
  expect_true(m$converged)
  expect_equal(stats::coef(m)[[2]], 0, tolerance = 1e-8)
})

test_that("the warning names the iteration the batch stopped on, not maxit", {
  # `delta` drops a missing window with na.rm, so a batch holding one settles as
  # soon as every OTHER window has converged. Here that is iteration 5 of 25,
  # and the three windows touching the NA stay unconverged. The message used to
  # read "after 25 iterations" whatever happened.
  y <- c(4, 6, NA, 9, 11, 10, 14, 19)
  msg <- tryCatch(
    rolling_slope_matrix(matrix(y, ncol = 1), 3, family = "quasipoisson"),
    warning = conditionMessage
  )
  expect_match(msg, "did not converge in 3 of 6 window fits", fixed = TRUE)
  expect_match(msg, "after 5 iterations (maxit = 25)", fixed = TRUE)
  expect_false(grepl("after 25 iterations", msg, fixed = TRUE))

  # a batch with nothing missing does run to maxit, and says so
  msg2 <- tryCatch(
    rolling_slope_matrix(
      matrix(rep(0, 4), ncol = 1),
      4,
      family = "quasipoisson"
    ),
    warning = conditionMessage
  )
  expect_match(msg2, "after 25 iterations (maxit = 25)", fixed = TRUE)
})
