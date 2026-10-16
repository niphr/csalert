# The v4 quasi-Poisson trend kernel, .v4_rolling_qp_offset(), against
# glm2::glm2() followed by summary.glm(). A claimed window MUST match within
# |kernel - glm2| <= V4K_ABS_TOL or |kernel - glm2| <= V4K_REL_TOL * |glm2|.
# A window where glm2 warns or errors MUST NOT be claimed. A window whose
# scaled deviance rise after iteration 1 is above V4K_RISE_TOL MUST NOT be
# claimed.

V4K_ABS_TOL <- 1e-10
V4K_RISE_TOL <- 1e-10
V4K_REL_TOL <- 1e-8
V4K_VALUES <- c("beta0", "beta1", "se", "p", "df")

# Fit one window with glm2 and summary.glm. Record every warning and error of
# both calls.
v4k_glm2_window <- function(y, off, tt) {
  messages <- character()
  d <- data.frame(y = y, t = tt)
  if (is.null(off)) {
    model <- y ~ t
  } else {
    d$off <- off
    model <- y ~ t + offset(off)
  }
  values <- tryCatch(
    withCallingHandlers(
      {
        fit <- glm2::glm2(model, family = stats::quasipoisson, data = d)
        s <- summary(fit)
        c(
          beta0 = stats::coef(fit)[["(Intercept)"]],
          beta1 = s$coefficients["t", "Estimate"],
          se = s$coefficients["t", "Std. Error"],
          p = s$coefficients["t", "Pr(>|t|)"],
          df = s$df.residual
        )
      },
      warning = function(w) {
        messages <<- c(messages, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      messages <<- c(messages, paste("error:", conditionMessage(e)))
      stats::setNames(rep(NA_real_, 5), V4K_VALUES)
    }
  )
  list(values = values, messages = messages)
}

# Run the kernel on the matrices, and glm2 on every window of every column.
# The result has one row per window.
v4k_run <- function(Y, OFF, TT, width) {
  seconds_kernel <- system.time(
    k <- .v4_rolling_qp_offset(Y, OFF, TT, width)
  )[["elapsed"]]
  grid <- expand.grid(end = width:nrow(Y), series = seq_len(ncol(Y)))
  seconds_glm2 <- system.time(
    ref <- lapply(seq_len(nrow(grid)), function(q) {
      rows <- (grid$end[q] - width + 1):grid$end[q]
      j <- grid$series[q]
      off <- if (is.null(OFF)) NULL else OFF[rows, j]
      v4k_glm2_window(Y[rows, j], off, TT[rows, j])
    })
  )[["elapsed"]]
  at <- cbind(grid$end, grid$series)
  y_windows <- lapply(seq_len(nrow(grid)), function(q) {
    Y[(grid$end[q] - width + 1):grid$end[q], grid$series[q]]
  })
  list(
    claimed = k$claimed[at],
    max_rise = k$max_rise[at],
    kernel = matrix(
      vapply(V4K_VALUES, function(nm) k[[nm]][at], numeric(nrow(at))),
      ncol = length(V4K_VALUES),
      dimnames = list(NULL, V4K_VALUES)
    ),
    glm2 = do.call(rbind, lapply(ref, `[[`, "values")),
    warned = vapply(ref, function(r) length(r$messages) > 0, logical(1)),
    messages = vapply(ref, function(r) paste(r$messages, collapse = "; "), ""),
    y = y_windows,
    seconds_kernel = seconds_kernel,
    seconds_glm2 = seconds_glm2
  )
}

# The number of claimed windows whose 5 values do not all match glm2.
v4k_mismatches <- function(run) {
  k <- run$kernel[run$claimed, , drop = FALSE]
  g <- run$glm2[run$claimed, , drop = FALSE]
  gap <- abs(k - g)
  ok <- !is.na(gap) & (gap <= V4K_ABS_TOL | gap <= V4K_REL_TOL * abs(g))
  sum(!ok)
}

# Random series in the shape of v1's call. The counts are Poisson with a
# log-linear trend, and the denominators are from 200 to 20,000. Time is
# row / (N + 2) inside a longer series of N rows. Each series gives `n_end`
# windows.
v4k_random <- function(width, n_series, n_end, with_offset = TRUE) {
  n_row <- width - 1 + n_end
  Y <- OFF <- TT <- matrix(NA_real_, n_row, n_series)
  for (j in seq_len(n_series)) {
    N <- sample(30:1000, 1)
    rows <- sample(0:(N - n_row), 1) + seq_len(n_row)
    den <- stats::rpois(n_row, exp(stats::runif(1, log(200), log(20000))))
    rate <- exp(stats::runif(1, log(1e-3), log(0.2)))
    slope <- stats::rnorm(1, 0, 0.15) * N
    tt <- rows / (N + 2)
    mu <- den * rate * exp(slope * (tt - mean(tt)))
    if (!with_offset) {
      mu <- rate * 1000 * exp(slope * (tt - mean(tt)))
    }
    Y[, j] <- stats::rpois(n_row, mu)
    OFF[, j] <- log(den)
    TT[, j] <- tt
  }
  if (!with_offset) {
    OFF <- NULL
  }
  list(Y = Y, OFF = OFF, TT = TT)
}

# Single windows of extreme shapes, where glm2 often warns. Each column is one
# window.
v4k_stress <- function(width, n_window) {
  Y <- OFF <- TT <- matrix(NA_real_, width, n_window)
  for (j in seq_len(n_window)) {
    Y[, j] <- switch(
      sample(1:4, 1),
      stats::rpois(width, exp(stats::runif(1, -1, 3))),
      sample(c(0, 0, 1, 2, 50, 500), width, replace = TRUE),
      round(exp(stats::rnorm(width, 2, 3))),
      stats::rpois(
        width,
        exp(seq(0, stats::runif(1, 2, 12), length.out = width))
      )
    )
    OFF[, j] <- stats::rnorm(width, 0, sample(c(0.1, 2, 6), 1))
    TT[, j] <- sort(stats::runif(width))
  }
  list(Y = Y, OFF = OFF, TT = TT)
}

set.seed(20261016)
v4k_sets <- list(
  random5 = c(v4k_random(5, 50, 20), width = 5),
  random6 = c(v4k_random(6, 50, 20), width = 6),
  no_offset = c(v4k_random(5, 10, 20, with_offset = FALSE), width = 5),
  stress5 = c(v4k_stress(5, 250), width = 5),
  stress6 = c(v4k_stress(6, 250), width = 6)
)
v4k_runs <- lapply(v4k_sets, function(s) v4k_run(s$Y, s$OFF, s$TT, s$width))

# The edge cases of the v1 reference test, data-raw/v1_reference_make.R. A
# case has `violates = TRUE` when it breaks a clean-window rule.
v4k_tt <- (11:15) / 22
v4k_off <- log(c(2010, 1985, 2003, 1968, 2022))
v4k_edge <- list(
  all_zero = list(y = c(0, 0, 0, 0, 0), violates = TRUE),
  separated_last = list(y = c(0, 0, 0, 0, 5), violates = TRUE),
  separated_first = list(y = c(1, 0, 0, 0, 0), violates = TRUE),
  near_all_zero = list(y = c(0, 0, 1, 0, 2), violates = FALSE),
  near_all_zero_ends = list(y = c(1, 0, 0, 0, 1), violates = FALSE),
  zeros_at_end = list(y = c(4, 3, 5, 0, 0), violates = FALSE),
  zeros_at_start = list(y = c(0, 0, 0, 5, 6), violates = FALSE),
  na_inside = list(y = c(5, NA, 7, 8, 9), violates = TRUE),
  few_non_na = list(y = c(NA, NA, 3, NA, NA), violates = TRUE),
  negative = list(y = c(3, -1, 4, 6, 7), violates = TRUE),
  zero_denominator = list(
    y = c(3, 5, 4, 6, 7),
    off = log(c(2000, 0, 1900, 2100, 2050)),
    violates = TRUE
  ),
  na_offset = list(
    y = c(3, 5, 4, 6, 7),
    off = log(c(2000, NA, 1900, 2100, 2050)),
    violates = TRUE
  ),
  zero_offset = list(
    y = c(3, 5, 4, 6, 7),
    off = c(0, 0, 0, 0, 0),
    violates = FALSE
  ),
  width2 = list(
    y = c(3, 5),
    off = v4k_off[1:2],
    tt = v4k_tt[1:2],
    violates = TRUE
  ),
  # The separated series of the v1 reference, as 16 windows of width 5.
  separated_series = list(
    y = c(4, 3, 5, 0, 0, 0, 0, 5, 6, 4, 1, 0, 0, 0, 0, 3, 4, 5, 6, 4),
    off = log(rep(2000, 20)),
    tt = (1:20) / 22,
    violates = NA
  )
)
v4k_edge_runs <- lapply(v4k_edge, function(case) {
  off <- if (is.null(case$off)) v4k_off else case$off
  tt <- if (is.null(case$tt)) v4k_tt else case$tt
  width <- min(length(case$y), 5L)
  v4k_run(matrix(case$y), matrix(off), matrix(tt), width)
})

# A window where glm2 halves the step at a rise of the deviance. Plain IRLS
# converges on it with no halving, so only the rise rule rejects it.
v4k_rise <- list(
  y = c(6, 9, 6, 87, 16),
  off = c(
    1.06631665670597,
    0.743591769897606,
    0.73442862435054,
    7.33417311376628,
    -5.1054881394386
  ),
  tt = c(
    0.214690217282623,
    0.227526461472735,
    0.28147080889903,
    0.366922228829935,
    0.421829380793497
  )
)
v4k_rise_run <- v4k_run(
  matrix(v4k_rise$y),
  matrix(v4k_rise$off),
  matrix(v4k_rise$tt),
  5
)

# A window where the main fit converges with no rise, but the null-deviance
# fit of glm2 does not converge within 25 iterations.
v4k_null <- list(
  y = c(50, 500, 1, 50, 50, 1),
  off = c(
    -3.296399708121,
    -15.442314511316,
    2.1355324726538,
    0.529066210303342,
    7.5007982312649,
    11.3890651613614
  ),
  tt = c(
    0.0255400310270488,
    0.0579890804365277,
    0.217017106479034,
    0.250275865197182,
    0.478436486795545,
    0.867893461370841
  )
)
v4k_null_run <- v4k_run(
  matrix(v4k_null$y),
  matrix(v4k_null$off),
  matrix(v4k_null$tt),
  6
)

# The window of v4k_rise with its offsets times 0.8212219. Its scaled
# deviance rise at iteration 2 is 3.7e-8, between the 1e-8 step-halving
# trigger of glm2 and 1e-7.
v4k_band <- list(
  y = v4k_rise$y,
  off = c(
    0.875682579783681,
    0.610653838402338,
    0.603128862701053,
    6.02298350349591,
    -4.19273861744745
  ),
  tt = v4k_rise$tt
)
v4k_band_run <- v4k_run(
  matrix(v4k_band$y),
  matrix(v4k_band$off),
  matrix(v4k_band$tt),
  5
)

v4k_all_runs <- c(
  v4k_runs,
  v4k_edge_runs,
  list(rise = v4k_rise_run, band = v4k_band_run, null_fit = v4k_null_run)
)

test_that("every claimed window matches glm2 and summary.glm", {
  for (nm in names(v4k_all_runs)) {
    expect_identical(v4k_mismatches(v4k_all_runs[[nm]]), 0L, label = nm)
  }
})

test_that("no window where glm2 warns or errors is claimed", {
  for (nm in names(v4k_all_runs)) {
    run <- v4k_all_runs[[nm]]
    expect_identical(sum(run$claimed & run$warned), 0L, label = nm)
  }
  # The stress windows MUST reach the warning paths of glm2.
  expect_gt(sum(v4k_runs$stress5$warned) + sum(v4k_runs$stress6$warned), 0)
})

test_that("the kernel claims at least 95% of the 2,000 random windows", {
  claimed <- c(v4k_runs$random5$claimed, v4k_runs$random6$claimed)
  expect_identical(length(claimed), 2000L)
  share <- mean(claimed)
  seconds_kernel <- v4k_runs$random5$seconds_kernel +
    v4k_runs$random6$seconds_kernel
  seconds_glm2 <- v4k_runs$random5$seconds_glm2 + v4k_runs$random6$seconds_glm2
  cat(sprintf(
    "\nv4 kernel: claimed %d of %d random windows (%.2f%%); kernel %.3f s, glm2 loop %.3f s\n",
    sum(claimed),
    length(claimed),
    100 * share,
    seconds_kernel,
    seconds_glm2
  ))
  expect_gte(share, 0.95)
})

test_that("the rise rule rejects a window where glm2 halves the step", {
  expect_match(
    v4k_rise_run$messages,
    "step size truncated due to increasing deviance",
    fixed = TRUE
  )
  expect_false(v4k_rise_run$claimed)
})

test_that("every claimed window has a scaled deviance rise of at most 1e-10", {
  for (nm in names(v4k_all_runs)) {
    run <- v4k_all_runs[[nm]]
    rise <- run$max_rise[run$claimed]
    expect_false(anyNA(rise), label = nm)
    expect_true(all(rise <= V4K_RISE_TOL), label = nm)
  }
})

test_that("claimed windows with a rise in (0, 1e-10] match glm2, which does not warn", {
  random <- v4k_runs[c("random5", "random6")]
  in_band <- lapply(random, function(run) {
    run$claimed & run$max_rise > 0 & run$max_rise <= V4K_RISE_TOL
  })
  n_band <- sum(vapply(in_band, sum, integer(1)))
  cat(sprintf("
v4 kernel: %d claimed random windows rise by (0, 1e-10]
", n_band))
  expect_gt(n_band, 0)
  for (nm in names(random)) {
    run <- random[[nm]]
    expect_identical(sum(run$warned[in_band[[nm]]]), 0L, label = nm)
    run$claimed <- in_band[[nm]]
    expect_identical(v4k_mismatches(run), 0L, label = nm)
  }
})

test_that("a window with a rise above 1e-10 where glm2 warns is not claimed", {
  # v4k_rise rises far above 1e-8. v4k_band rises between 1e-8 and 1e-7, so a
  # rise tolerance of 1e-7 would claim it.
  expect_gte(v4k_rise_run$max_rise, 1e-8)
  expect_gte(v4k_band_run$max_rise, 1e-8)
  expect_lte(v4k_band_run$max_rise, 1e-7)
  for (run in list(v4k_rise_run, v4k_band_run)) {
    expect_match(
      run$messages,
      "step size truncated due to increasing deviance",
      fixed = TRUE
    )
    expect_false(run$claimed)
  }
})

test_that("the kernel claims the same 1971 of 2,000 random windows as round 1", {
  claimed <- c(v4k_runs$random5$claimed, v4k_runs$random6$claimed)
  expect_identical(sum(claimed), 1971L)
  expect_identical(
    which(!claimed),
    c(
      321L, 322L, 421L, 422L, 424L, 425L, 787L, 788L, 796L, 797L, 798L,
      923L, 924L, 925L, 936L, 937L, 938L, 939L, 940L, 1279L, 1280L,
      1321L, 1322L, 1323L, 1324L, 1325L, 1326L, 1327L, 1437L
    )
  )
})

test_that("the null-fit rule rejects a window whose null-deviance fit fails", {
  expect_match(
    v4k_null_run$messages,
    "fitting to calculate the null deviance did not converge",
    fixed = TRUE
  )
  expect_false(v4k_null_run$claimed)
})

test_that("every edge case that breaks a rule or makes glm2 warn is not claimed", {
  for (nm in names(v4k_edge_runs)) {
    run <- v4k_edge_runs[[nm]]
    violates <- v4k_edge[[nm]]$violates
    if (is.na(violates)) {
      # The rule for each window of a series: every value finite, counts >= 0,
      # at least 2 counts above 0.
      violates <- vapply(
        run$y,
        function(y) any(!is.finite(y)) || any(y < 0) || sum(y > 0) < 2,
        logical(1)
      )
    }
    must_fall_back <- violates | run$warned
    expect_false(any(run$claimed[must_fall_back]), label = nm)
    expect_false(anyNA(run$claimed), label = nm)
  }
  # The separated series MUST hold windows that break a rule and windows that
  # do not.
  y_sep <- v4k_edge_runs$separated_series$y
  expect_true(any(vapply(y_sep, function(y) sum(y > 0) < 2, logical(1))))
  expect_true(any(v4k_edge_runs$separated_series$claimed))
})

test_that("the standard error uses the weights of the last least-squares step", {
  # Series 14 of the width-6 random set, the window that ends at row 17.
  # glm2 stores the weights of its last least-squares step, which differ
  # from its final fitted means by about 1.7e-4.
  s <- v4k_sets$random6
  rows <- 12:17
  d <- data.frame(y = s$Y[rows, 14], t = s$TT[rows, 14], off = s$OFF[rows, 14])
  fit <- glm2::glm2(y ~ t + offset(off), family = stats::quasipoisson, data = d)
  w_last <- unname(fit$weights)
  mu_final <- unname(fit$fitted.values)
  expect_gt(max(abs(w_last - mu_final) / mu_final), 1e-5)

  # The standard error from the final fitted means misses summary.glm by more
  # than the tolerance, so the match test can tell the two apart. Time is
  # centred, which leaves the slope's standard error unchanged.
  x <- cbind(1, d$t - mean(d$t))
  r <- (d$y - mu_final) / mu_final
  se_final <- sqrt(
    sum(mu_final * r^2) / 4 * solve(crossprod(x * mu_final, x))[2, 2]
  )
  se_glm2 <- summary(fit)$coefficients["t", "Std. Error"]
  expect_gt(abs(se_final - se_glm2), V4K_REL_TOL * se_glm2)

  k <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, 6)
  expect_true(k$claimed[17, 14])
  expect_lte(abs(k$se[17, 14] - se_glm2), V4K_REL_TOL * se_glm2)
})

test_that("the kernel returns matrices like Y with NA before the first full window", {
  s <- v4k_sets$random5
  k <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, 5)
  expect_named(k, c(V4K_VALUES, "claimed", "max_rise"))
  for (nm in names(k)) {
    expect_identical(dim(k[[nm]]), dim(s$Y), label = nm)
    expect_true(all(is.na(k[[nm]][1:4, ])), label = nm)
  }
  expect_type(k$claimed, "logical")
  expect_false(anyNA(k$claimed[5:nrow(s$Y), ]))
  unclaimed <- !is.na(k$claimed) & !k$claimed
  for (nm in V4K_VALUES) {
    expect_true(all(is.na(k[[nm]][unclaimed])), label = nm)
  }

  short <- .v4_rolling_qp_offset(s$Y[1:3, ], s$OFF[1:3, ], s$TT[1:3, ], 5)
  expect_true(all(vapply(short, function(m) all(is.na(m)), logical(1))))
})

# The outputs that the v1 method uses since 2026.10.17: the scaled
# covariance, the dispersion, the convergence and separation flags, and the
# NA-tolerant mode. They MUST match glm2::glm2() with na.omit, summary.glm()
# and vcov() within the same tolerance as the values above.
V4K_FULL <- c(V4K_VALUES, "var_b0", "cov_b0b1", "phi")

# Fit one window with glm2, and return the 8 values of the extended output.
# glm2 drops the rows with an NA, as na.omit does.
v4k_glm2_full <- function(y, off, tt) {
  messages <- character()
  d <- data.frame(y = y, t = tt)
  if (is.null(off)) {
    model <- y ~ t
  } else {
    d$off <- off
    model <- y ~ t + offset(off)
  }
  values <- tryCatch(
    withCallingHandlers(
      {
        fit <- glm2::glm2(model, family = stats::quasipoisson, data = d)
        s <- summary(fit)
        v <- stats::vcov(fit)
        c(
          beta0 = stats::coef(fit)[["(Intercept)"]],
          beta1 = s$coefficients["t", "Estimate"],
          se = s$coefficients["t", "Std. Error"],
          p = s$coefficients["t", "Pr(>|t|)"],
          df = s$df.residual,
          var_b0 = v["(Intercept)", "(Intercept)"],
          cov_b0b1 = v["(Intercept)", "t"],
          phi = s$dispersion
        )
      },
      warning = function(w) {
        messages <<- c(messages, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      messages <<- c(messages, paste("error:", conditionMessage(e)))
      stats::setNames(rep(NA_real_, length(V4K_FULL)), V4K_FULL)
    }
  )
  list(values = values, warned = length(messages) > 0)
}

# Compare the extended kernel output with glm2 in the windows that `pick`
# selects. The result counts the windows compared, and the values outside the
# tolerance.
v4k_compare_full <- function(k, Y, OFF, TT, width, pick) {
  at <- which(pick, arr.ind = TRUE)
  n_bad <- 0L
  n_cmp <- 0L
  for (q in seq_len(nrow(at))) {
    rows <- (at[q, 1] - width + 1):at[q, 1]
    j <- at[q, 2]
    off <- if (is.null(OFF)) NULL else OFF[rows, j]
    g <- v4k_glm2_full(Y[rows, j], off, TT[rows, j])
    if (g$warned) {
      next
    }
    kv <- vapply(V4K_FULL, function(nm) k[[nm]][at[q, 1], j], numeric(1))
    gap <- abs(kv - g$values)
    ok <- !is.na(gap) &
      (gap <= V4K_ABS_TOL | gap <= V4K_REL_TOL * abs(g$values))
    n_bad <- n_bad + sum(!ok)
    n_cmp <- n_cmp + 1L
  }
  list(compared = n_cmp, mismatches = n_bad)
}

# Random series with NA counts and NA offsets.
set.seed(20261017)
v4k_na <- v4k_random(5, 40, 20)
v4k_na$Y[sample(length(v4k_na$Y), 120)] <- NA
v4k_na$OFF[sample(length(v4k_na$OFF), 40)] <- NA
v4k_na_k <- .v4_rolling_qp_offset(
  v4k_na$Y,
  v4k_na$OFF,
  v4k_na$TT,
  5,
  na_rm = TRUE,
  extended = TRUE
)

test_that("extended = TRUE adds 7 matrices and leaves the other 7 unchanged", {
  for (nm in c("random5", "stress5", "no_offset")) {
    s <- v4k_sets[[nm]]
    k <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, s$width)
    k_ext <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, s$width, extended = TRUE)
    expect_named(
      k_ext,
      c(
        names(k),
        "var_b0",
        "cov_b0b1",
        "phi",
        "converged",
        "separated",
        "n_used",
        "n_pos"
      )
    )
    expect_identical(k_ext[names(k)], k, label = nm)
    # Every claimed window converged.
    expect_true(all(k_ext$converged[k$claimed %in% TRUE]), label = nm)
  }
})

test_that("var_b0, cov_b0b1 and phi match glm2 and vcov() in every claimed window", {
  for (nm in c("random5", "no_offset", "stress5")) {
    s <- v4k_sets[[nm]]
    k <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, s$width, extended = TRUE)
    pick <- k$claimed & !is.na(k$claimed)
    res <- v4k_compare_full(k, s$Y, s$OFF, s$TT, s$width, pick)
    expect_gt(res$compared, 0L)
    expect_identical(res$mismatches, 0L, label = nm)
  }
})

test_that("na_rm = TRUE matches glm2 with na.omit in windows with NA", {
  k <- v4k_na_k
  pick <- k$converged %in% TRUE & !k$separated
  res <- v4k_compare_full(k, v4k_na$Y, v4k_na$OFF, v4k_na$TT, 5, pick)
  cat(sprintf(
    "\nv4 kernel, na_rm = TRUE: %d windows match glm2, %d of them with NA rows\n",
    res$compared,
    sum(pick & k$n_used < 5)
  ))
  expect_identical(res$mismatches, 0L)
  expect_gt(sum(pick & k$n_used < 5), 0L)
  # The degrees of freedom are the used rows minus 2.
  expect_identical(k$df[pick], k$n_used[pick] - 2)
})

test_that("na_rm = TRUE fits no window with fewer than 3 used rows", {
  k <- v4k_na_k
  few <- k$n_used < 3 & !is.na(k$n_used)
  expect_gt(sum(few), 0L)
  expect_false(any(k$converged[few]))
  for (nm in V4K_FULL) {
    expect_true(all(is.na(k[[nm]][few])), label = nm)
  }
})

test_that("na_rm = TRUE converges where glm2 fits 3 or more rows without a warning", {
  k <- v4k_na_k
  at <- which(k$n_used >= 3 & !k$separated, arr.ind = TRUE)
  missed <- 0L
  for (q in seq_len(nrow(at))) {
    rows <- (at[q, 1] - 4):at[q, 1]
    j <- at[q, 2]
    g <- v4k_glm2_full(v4k_na$Y[rows, j], v4k_na$OFF[rows, j], v4k_na$TT[rows, j])
    if (!g$warned && !k$converged[at[q, 1], j]) {
      missed <- missed + 1L
    }
  }
  expect_gt(nrow(at), 0L)
  expect_identical(missed, 0L)
})

test_that("na_rm = TRUE without NA claims the same windows as the default", {
  s <- v4k_sets$random5
  k <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, 5)
  k_na <- .v4_rolling_qp_offset(s$Y, s$OFF, s$TT, 5, na_rm = TRUE)
  expect_identical(k_na$claimed, k$claimed)
  claimed <- k$claimed %in% TRUE
  for (nm in V4K_VALUES) {
    gap <- abs(k_na[[nm]][claimed] - k[[nm]][claimed])
    expect_true(
      all(gap <= V4K_ABS_TOL | gap <= V4K_REL_TOL * abs(k[[nm]][claimed])),
      label = nm
    )
  }
})

test_that("the separated flag marks the windows whose counts above 0 sit at one end", {
  windows <- list(
    separated_last = list(y = c(0, 0, 0, 0, 5), separated = TRUE),
    separated_first = list(y = c(1, 0, 0, 0, 0), separated = TRUE),
    single_inside = list(y = c(0, 0, 5, 0, 0), separated = FALSE),
    two_positive = list(y = c(0, 0, 1, 0, 2), separated = FALSE),
    all_zero = list(y = c(0, 0, 0, 0, 0), separated = FALSE),
    last_used = list(y = c(NA, 0, 0, 3, NA), separated = TRUE)
  )
  for (nm in names(windows)) {
    w <- windows[[nm]]
    k <- .v4_rolling_qp_offset(
      matrix(w$y),
      matrix(v4k_off),
      matrix(v4k_tt),
      5,
      na_rm = TRUE,
      extended = TRUE
    )
    expect_identical(k$separated[5, 1], w$separated, label = nm)
  }
  # Plain IRLS meets the deviance rule on a separated window, as glm2 does,
  # so only the flag shows it.
  k <- .v4_rolling_qp_offset(
    matrix(c(0, 0, 0, 0, 5)),
    matrix(v4k_off),
    matrix(v4k_tt),
    5,
    na_rm = TRUE,
    extended = TRUE
  )
  expect_true(k$converged[5, 1])
  expect_false(k$claimed[5, 1])
})

test_that("a window where glm2 halves the step converges, and na_rm = TRUE reports it", {
  k <- .v4_rolling_qp_offset(
    matrix(v4k_rise$y),
    matrix(v4k_rise$off),
    matrix(v4k_rise$tt),
    5,
    na_rm = TRUE,
    extended = TRUE
  )
  expect_false(k$claimed[5, 1])
  expect_true(k$converged[5, 1])
  expect_false(is.na(k$beta1[5, 1]))
})
