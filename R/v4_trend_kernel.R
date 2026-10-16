# The quasi-Poisson trend kernel of the v4 methods. It fits every rolling
# window of every series at once, and it calls no csalert function outside the
# R/v4_*.R files.

# A scaled deviance rise at or below 1e-10 is rounding at convergence. glm2
# 1.2.1 halves the step at 1e-8, so this rule is 100 times stricter.
.V4_RISE_TOL <- 1e-10

# With `na_rm = TRUE`, the kernel fits a window only when at least this many
# rows remain, so that the dispersion has at least 1 degree of freedom.
.V4_MIN_ROWS <- 3L

#' Fit a rolling quasi-Poisson trend with an offset in every window at once
#'
#' The function fits `y ~ t + offset(off)` with the quasi-Poisson family by
#' IRLS, in each window of `width` rows of each column of `Y`. It claims a
#' window only when its fit follows the same path as `glm2::glm2()`.
#'
#' A window is claimed only if all of these hold:
#' - every count, offset and time value is finite, and every count is >= 0;
#' - at least 2 counts are above 0, and `width` is at least 3;
#' - plain IRLS from `mu = y + 0.1` converges under the deviance rule of
#'   `glm2::glm.fit2()` within `maxit` iterations;
#' - the scaled deviance change after iteration 1 is never above 1e-10, 100
#'   times below the default step-halving trigger of `glm2::glm.fit2()`;
#' - every value stays finite, and every fitted mean stays above 0;
#' - the smallest IRLS weight of the last iteration is at least 1e-6 times the
#'   largest;
#' - the weighted design of the last iteration has a 2-norm reciprocal
#'   condition number of at least 1e-10;
#' - with an offset, the intercept-only fit that `glm2::glm2()` runs for the
#'   null deviance obeys the same rules.
#'
#' With `na_rm = TRUE`, a row with a non-finite count, offset or time value
#' gets weight 0, and the other rows keep their time values. The first rule
#' then applies to the used rows only. The kernel fits every window that has
#' at least 3 used rows and no negative count. The degrees of freedom are the
#' number of used rows minus 2.
#'
#' The standard error matches `summary.glm()`. It uses the weights of the last
#' weighted least-squares step and the final fitted means. The Pearson
#' dispersion has `width - 2` degrees of freedom and no floor.
#'
#' @param Y A numeric matrix of counts. Rows are time positions and columns
#'   are series.
#' @param OFF A numeric matrix like `Y` of offsets, or NULL for no offset.
#' @param TT A numeric matrix like `Y` of time covariate values.
#' @param width The number of rows in a window.
#' @param maxit The maximum number of IRLS iterations.
#' @param epsilon The tolerance of the deviance convergence rule.
#' @param na_rm If TRUE, give weight 0 to the rows with a non-finite value,
#'   and report the values of every converged window.
#' @param extended If TRUE, also return `var_b0`, `cov_b0b1`, `phi`,
#'   `converged`, `separated`, `n_used` and `n_pos`.
#' @return A list of 7 matrices with the dimensions of `Y`: `beta0`, `beta1`,
#'   `se`, `p`, `df`, `claimed` and `max_rise`. The window of row `i` holds
#'   rows `i - width + 1` to `i`. Rows before `width` are NA. With
#'   `na_rm = FALSE`, an unclaimed window has `claimed = FALSE` and NA in
#'   `beta0`, `beta1`, `se`, `p` and `df`. With `na_rm = TRUE`, a window has
#'   values where `converged` is TRUE. `max_rise` is the largest scaled
#'   deviance change after iteration 1 in the fits that the kernel ran for the
#'   window. It counts the changes up to the first one above 1e-10. It is NA
#'   where the kernel ran no fit, and -Inf where no fit has a finite change
#'   after iteration 1.
#'
#'   With `extended = TRUE`, the list holds 7 more matrices:
#'   - `var_b0` and `cov_b0b1`: the variance of the intercept and its
#'     covariance with the slope. Both include the dispersion, as
#'     `summary.glm()$cov.scaled` does. The variance of the slope is `se^2`.
#'   - `phi`: the Pearson dispersion.
#'   - `converged`: TRUE where the kernel fitted the window, IRLS met the
#'     deviance rule within `maxit` iterations, and every value is finite. A
#'     rise of the deviance does not stop the fit. FALSE where the kernel ran
#'     no fit.
#'   - `separated`: TRUE where every used count above 0 sits at the smallest
#'     used time value, or every one at the largest. FALSE where no used count
#'     is above 0. In both cases, the maximum-likelihood estimate does not
#'     exist. IRLS can still meet the deviance rule, because the fitted means
#'     of the zero counts go to 0.
#'   - `n_used`: the number of rows with a finite count, offset and time value.
#'   - `n_pos`: the number of those rows with a count above 0.
#' @noRd
.v4_rolling_qp_offset <- function(
  Y,
  OFF = NULL,
  TT,
  width,
  maxit = 25L,
  epsilon = 1e-8,
  na_rm = FALSE,
  extended = FALSE
) {
  Y <- as.matrix(Y)
  TT <- as.matrix(TT)
  n_row <- nrow(Y)
  n_col <- ncol(Y)
  has_offset <- !is.null(OFF)
  if (has_offset) {
    OFF <- as.matrix(OFF)
  } else {
    OFF <- matrix(0, n_row, n_col)
  }
  stopifnot(
    identical(dim(OFF), dim(Y)),
    identical(dim(TT), dim(Y)),
    length(width) == 1L,
    width >= 1
  )

  out <- .v4_rolling_empty_out(n_row, n_col, extended)
  if (n_row < width) {
    return(out)
  }

  # One column per window. The windows of a series are in order of end row,
  # and the series follow each other.
  n_end <- n_row - width + 1L
  within_series <- as.vector(outer(seq_len(width), seq_len(n_end) - 1L, "+"))
  cell <- rep(within_series, n_col) +
    rep((seq_len(n_col) - 1L) * n_row, each = width * n_end)
  y <- matrix(as.numeric(Y[cell]), nrow = width)
  off <- matrix(as.numeric(OFF[cell]), nrow = width)
  tt <- matrix(as.numeric(TT[cell]), nrow = width)
  n_win <- ncol(y)

  all_finite <- is.finite(y) & is.finite(off) & is.finite(tt)
  y_zeroed <- y
  y_zeroed[!all_finite] <- 0
  n_used <- colSums(all_finite)
  n_pos <- colSums(y_zeroed > 0)
  no_negative <- colSums(y_zeroed < 0) == 0
  prep <- .v4_rolling_prepare(
    y,
    off,
    tt,
    all_finite,
    n_used,
    n_pos,
    no_negative,
    width,
    na_rm
  )
  y <- prep$y
  off <- prep$off
  tt <- prep$tt
  pw <- prep$pw
  fit_set <- prep$fit_set
  eligible <- prep$eligible

  claimed <- rep(FALSE, n_win)
  converged <- rep(FALSE, n_win)
  max_rise <- rep(NA_real_, n_win)
  values <- matrix(NA_real_, n_win, 8L)
  colnames(values) <- c(
    "beta0",
    "beta1",
    "se",
    "p",
    "df",
    "var_b0",
    "cov_b0b1",
    "phi"
  )

  candidate <- which(fit_set)
  if (length(candidate)) {
    fit <- .v4_qp_irls(
      y[, candidate, drop = FALSE],
      off[, candidate, drop = FALSE],
      tt[, candidate, drop = FALSE],
      with_slope = TRUE,
      maxit = maxit,
      epsilon = epsilon,
      pw = if (na_rm) pw[, candidate, drop = FALSE]
    )
    claimed[candidate] <- fit$clean & eligible[candidate]
    converged[candidate] <- fit$converged
    max_rise[candidate] <- fit$max_rise
    values[candidate, ] <- cbind(
      fit$beta0,
      fit$beta1,
      fit$se,
      fit$p,
      fit$df,
      fit$var_b0,
      fit$cov_b0b1,
      fit$phi
    )
  }

  candidate <- which(claimed)
  if (has_offset && length(candidate)) {
    null_fit <- .v4_qp_irls(
      y[, candidate, drop = FALSE],
      off[, candidate, drop = FALSE],
      tt[, candidate, drop = FALSE],
      with_slope = FALSE,
      maxit = maxit,
      epsilon = epsilon,
      pw = if (na_rm) pw[, candidate, drop = FALSE]
    )
    claimed[candidate] <- null_fit$clean
    max_rise[candidate] <- pmax(max_rise[candidate], null_fit$max_rise)
  }
  if (na_rm) {
    values[!converged, ] <- NA_real_
  } else {
    values[!claimed, ] <- NA_real_
  }

  rows <- width:n_row
  keep <- if (extended) colnames(values) else colnames(values)[1:5]
  for (nm in keep) {
    out[[nm]][rows, ] <- matrix(values[, nm], n_end, n_col)
  }
  out$claimed[rows, ] <- matrix(claimed, n_end, n_col)
  out$max_rise[rows, ] <- matrix(max_rise, n_end, n_col)
  if (extended) {
    out <- .v4_rolling_fill_extended(
      out,
      rows,
      tt,
      all_finite,
      y_zeroed,
      converged,
      n_used,
      n_pos
    )
  }
  return(out)
}

# The windows that .v4_rolling_qp_offset() fits (`fit_set`) and those it can
# claim (`eligible`). With `na_rm = TRUE`, `pw` gives a row without a finite
# value weight 0, and `y`, `off` and `tt` hold 0 in that row. With
# `na_rm = FALSE`, `pw` is NULL and `y`, `off` and `tt` are unchanged.
.v4_rolling_prepare <- function(
  y,
  off,
  tt,
  all_finite,
  n_used,
  n_pos,
  no_negative,
  width,
  na_rm
) {
  if (na_rm) {
    # A row without a finite value gets weight 0. Its placeholder values keep
    # every step finite and do not change the fit.
    pw <- all_finite * 1
    y[!all_finite] <- 0
    off[!all_finite] <- 0
    tt[!all_finite] <- 0
    fit_set <- n_used >= .V4_MIN_ROWS & no_negative
    eligible <- fit_set & n_pos >= 2
  } else {
    pw <- NULL
    eligible <- colSums(!all_finite) == 0 & width >= 3
    eligible <- eligible & no_negative & n_pos >= 2
    fit_set <- eligible
  }
  return(list(
    y = y,
    off = off,
    tt = tt,
    pw = pw,
    fit_set = fit_set,
    eligible = eligible
  ))
}

# The list that .v4_rolling_qp_offset() returns, with every matrix all NA.
# With `extended = TRUE` it also holds the 7 extended matrices.
.v4_rolling_empty_out <- function(n_row, n_col, extended) {
  empty <- matrix(NA_real_, n_row, n_col)
  out <- list(
    beta0 = empty,
    beta1 = empty,
    se = empty,
    p = empty,
    df = empty,
    claimed = matrix(NA, n_row, n_col),
    max_rise = empty
  )
  if (extended) {
    out$var_b0 <- empty
    out$cov_b0b1 <- empty
    out$phi <- empty
    out$converged <- matrix(NA, n_row, n_col)
    out$separated <- matrix(NA, n_row, n_col)
    out$n_used <- empty
    out$n_pos <- empty
  }
  return(out)
}

# Write `converged`, `separated`, `n_used` and `n_pos` of each window into the
# rows `rows` of `out`. The windows are the columns of `tt`.
.v4_rolling_fill_extended <- function(
  out,
  rows,
  tt,
  all_finite,
  y_zeroed,
  converged,
  n_used,
  n_pos
) {
  n_end <- length(rows)
  n_col <- ncol(out$converged)
  # The smallest and largest time value of the used rows, and of the used
  # rows with a count above 0.
  masked_t <- function(mask, fill) {
    m <- tt
    m[!mask] <- fill
    return(m)
  }
  pos <- all_finite & y_zeroed > 0
  t_min <- matrixStats::colMins(masked_t(all_finite, Inf))
  t_max <- matrixStats::colMaxs(masked_t(all_finite, -Inf))
  t_pos_min <- matrixStats::colMins(masked_t(pos, Inf))
  t_pos_max <- matrixStats::colMaxs(masked_t(pos, -Inf))
  separated <- n_pos >= 1 & (t_pos_max <= t_min | t_pos_min >= t_max)
  out$converged[rows, ] <- matrix(converged, n_end, n_col)
  out$separated[rows, ] <- matrix(separated, n_end, n_col)
  out$n_used[rows, ] <- matrix(as.numeric(n_used), n_end, n_col)
  out$n_pos[rows, ] <- matrix(as.numeric(n_pos), n_end, n_col)
  return(out)
}

# The quasi-Poisson deviance of each column. It equals
# sum(quasipoisson()$dev.resids(y, mu, 1)). Prior weights `pw`, when given,
# multiply each term.
.v4_qp_deviance <- function(y, mu, pw = NULL) {
  y_log_ratio <- y * log(y / mu)
  y_log_ratio[y == 0] <- 0
  terms <- y_log_ratio - (y - mu)
  if (!is.null(pw)) {
    terms <- terms * pw
  }
  return(2 * colSums(terms))
}

# Plain IRLS for the quasi-Poisson log link, over the columns of `y` at once.
# With `with_slope = TRUE` the model is `y ~ t + offset(off)`. With
# `with_slope = FALSE` it is `y ~ 1 + offset(off)`, the null-deviance fit of
# glm2::glm2(). `pw`, when given, holds prior weights of 0 or 1.
#
# The function returns `clean`, which is TRUE for a column that obeys every
# rule of .v4_rolling_qp_offset(), and `converged`. It also returns
# `max_rise`, the largest scaled deviance change after iteration 1, up to the
# first change above .V4_RISE_TOL. A rise does not stop the fit. With a slope
# it also returns, for every converged column, the values that summary.glm()
# reports for the coefficient of `t`, and the scaled covariance.
.v4_qp_irls <- function(y, off, tt, with_slope, maxit, epsilon, pw = NULL) {
  w_n <- nrow(y)
  n_win <- ncol(y)
  # Centre time in each window, for numerical stability.
  if (is.null(pw)) {
    t_mean <- colMeans(tt)
    df_all <- rep(w_n - 2, n_win)
  } else {
    t_mean <- colSums(pw * tt) / colSums(pw)
    df_all <- colSums(pw) - 2
  }
  tc <- tt - rep(t_mean, each = w_n)

  converged <- rep(FALSE, n_win)
  rose <- rep(FALSE, n_win)
  max_rise <- rep(-Inf, n_win)
  a_fit <- rep(NA_real_, n_win)
  b_fit <- rep(NA_real_, n_win)
  w_last <- matrix(NA_real_, w_n, n_win)
  mu_last <- matrix(NA_real_, w_n, n_win)

  # glm.fit2() starts from mu = y + 0.1 and eta = log(mu), without the offset.
  active <- seq_len(n_win)
  mu <- y + 0.1
  eta <- log(mu)
  dev_old <- .v4_qp_deviance(y, mu, pw)

  for (iter in seq_len(maxit)) {
    if (!length(active)) {
      break
    }
    ya <- y[, active, drop = FALSE]
    offa <- off[, active, drop = FALSE]
    tca <- tc[, active, drop = FALSE]
    pwa <- if (!is.null(pw)) pw[, active, drop = FALSE]

    # The weighted least-squares step. The weight is mu, the square of the
    # sqrt(mu) that glm.fit2() passes to lm.fit().
    w <- mu
    if (!is.null(pw)) {
      w <- w * pwa
    }
    z <- eta - offa + (ya - mu) / mu
    sum_w <- colSums(w)
    if (with_slope) {
      t_w <- colSums(w * tca) / sum_w
      dev_t <- tca - rep(t_w, each = w_n)
      b <- colSums(w * dev_t * z) / colSums(w * dev_t * dev_t)
      a <- colSums(w * z) / sum_w - b * t_w
      eta_new <- rep(a, each = w_n) + rep(b, each = w_n) * tca + offa
    } else {
      b <- rep(0, length(active))
      a <- colSums(w * z) / sum_w
      eta_new <- rep(a, each = w_n) + offa
    }
    mu_new <- exp(eta_new)
    if (!is.null(pw)) {
      # A placeholder row keeps mu = 1, so the next step stays finite.
      unused <- pwa == 0
      eta_new[unused] <- 0
      mu_new[unused] <- 1
    }
    dev <- .v4_qp_deviance(ya, mu_new, pwa)

    bad <- !is.finite(a) |
      !is.finite(b) |
      !is.finite(dev) |
      colSums(!is.finite(z) | !is.finite(w)) > 0 |
      colSums(!is.finite(mu_new) | mu_new <= 0) > 0
    ratio <- (dev - dev_old) / (0.1 + abs(dev))
    # glm.fit2() halves the step when this ratio is >= epsilon after
    # iteration 1. The kernel does not claim a window with a rise above
    # .V4_RISE_TOL, and it stops recording max_rise there.
    if (iter > 1L) {
      track <- !rose[active]
      max_rise[active[track]] <- pmax(
        max_rise[active[track]],
        ratio[track],
        na.rm = TRUE
      )
      rose[active[!bad & ratio > .V4_RISE_TOL]] <- TRUE
    }
    done_now <- !bad & abs(ratio) < epsilon

    done <- active[done_now]
    converged[done] <- TRUE
    a_fit[done] <- a[done_now]
    b_fit[done] <- b[done_now]
    w_last[, done] <- w[, done_now]
    mu_last[, done] <- mu_new[, done_now]

    going <- !bad & !done_now
    active <- active[going]
    mu <- mu_new[, going, drop = FALSE]
    eta <- eta_new[, going, drop = FALSE]
    dev_old <- dev[going]
  }

  clean <- converged & !rose
  done <- which(converged)
  w_done <- w_last[, done, drop = FALSE]
  mu_done <- mu_last[, done, drop = FALSE]
  w_range <- w_done
  mu_range <- mu_done
  if (!is.null(pw)) {
    # The extremes are over the used rows only.
    unused <- pw[, done, drop = FALSE] == 0
    w_range[unused] <- NA_real_
    mu_range[unused] <- NA_real_
  }
  sum_w <- colSums(w_done)
  weights_ok <- matrixStats::colMins(w_range, na.rm = TRUE) >=
    1e-6 * matrixStats::colMaxs(w_range, na.rm = TRUE)
  weights_ok <- weights_ok &
    matrixStats::colMins(mu_range, na.rm = TRUE) >=
      1e-6 * matrixStats::colMaxs(mu_range, na.rm = TRUE)
  clean[done] <- clean[done] & weights_ok

  if (!with_slope) {
    return(list(clean = clean, converged = converged, max_rise = max_rise))
  }

  # The weighted design of the last step, with the uncentred time of glm2.
  # Its Gram matrix is [s, s * m; s * m, ss + s * m^2]. Here s is the weight
  # sum, m is the weighted mean time and ss is the weighted sum of squares
  # about m.
  tc_done <- tc[, done, drop = FALSE]
  t_w <- colSums(w_done * tc_done) / sum_w
  dev_t <- tc_done - rep(t_w, each = w_n)
  ss <- colSums(w_done * dev_t * dev_t)
  m <- t_w + t_mean[done]
  trace_g <- sum_w + ss + sum_w * m * m
  det_g <- sum_w * ss
  l_max <- (trace_g + sqrt(pmax(trace_g * trace_g - 4 * det_g, 0))) / 2
  rcond_ok <- is.finite(l_max) & sqrt((det_g / l_max) / l_max) >= 1e-10
  clean[done] <- clean[done] & rcond_ok

  # summary.glm(): the dispersion uses the working weights of the last step
  # and the working residuals of the final fitted means.
  y_done <- y[, done, drop = FALSE]
  df <- df_all[done]
  phi <- colSums(w_done * ((y_done - mu_done) / mu_done)^2) / df
  se <- sqrt(phi / ss)
  p <- 2 * stats::pt(-abs(b_fit[done] / se), df)
  clean[done] <- clean[done] & is.finite(se) & se > 0 & is.finite(p)
  # The inverse of the Gram matrix, times the dispersion.
  var_b0 <- phi * (1 / sum_w + m * m / ss)
  cov_b0b1 <- -phi * m / ss

  beta0 <- a_fit[done] - b_fit[done] * t_mean[done]
  converged[done] <- is.finite(beta0) &
    is.finite(b_fit[done]) &
    is.finite(se) &
    is.finite(p) &
    is.finite(phi) &
    is.finite(var_b0) &
    is.finite(cov_b0b1)

  fill <- function(v) {
    out <- rep(NA_real_, n_win)
    out[done] <- v
    return(out)
  }
  return(list(
    clean = clean,
    converged = converged,
    max_rise = max_rise,
    beta0 = fill(beta0),
    beta1 = fill(b_fit[done]),
    se = fill(se),
    p = fill(p),
    df = fill(df),
    var_b0 = fill(var_b0),
    cov_b0b1 = fill(cov_b0b1),
    phi = fill(phi)
  ))
}
