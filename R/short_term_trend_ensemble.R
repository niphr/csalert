# Batched short-term trend on a csfmt_ensemble_v3.
#
# The fast path: a fixed closed-form OLS slope kernel applied down every draw
# column at once (the "shared design matrix"). For a window of width w the slope
# weights depend only on w, so the rolling slope is a fixed linear filter over the
# weeks x draws matrix -- no per-draw, per-window model fit. Implemented with
# colCumsums (one pass) + padded differences. Bit-identical to per-column OLS.
#
# Seam-safe across stacked series: the rolling sums are computed over the whole
# column, then rows where time_series_internal_id < width are masked to NA --
# which is exactly the set of windows that would straddle a series boundary
# (internal_id resets to 1 per series).
#
# family = "quasipoisson" and family = "binomial" replace that closed form with
# IRLS, which is weighted least squares repeated a few times. It stays a filter:
# every window of every draw advances one iteration together, and no window ever
# reaches stats::glm.
#
# A window can also fail to converge. Complete or quasi-complete separation
# drives the slope to infinity. The iteration then returns whatever iterate
# maxit stopped on, which is finite and absurd. The kernel tracks the step size
# of each window separately. A window is converged only when its own step falls
# under tol. Everywhere else beta0, beta1 and se are NA.
#
# colCumsums cannot carry the weighted sums, and that is not an oversight. A
# working weight belongs to a (row, window) pair, not to a row alone. Row r sits
# at a different local time in each of the `width` windows holding it, so its eta
# and its mu differ in each one. A cumulative sum can only roll a quantity
# indexed by the row. The weighted sums are therefore accumulated over the
# `width` lagged slices of Y, which costs the O(width x rows x draws) the
# identity path already pays for `Stx`.

#' Rolling regression slope down every column of a matrix
#'
#' Fits `y ~ 1 + t`, with `t` from 1 to `width`, to each window of `width` rows in
#' every column. It is the kernel of the ensemble method of [short_term_trend()].
#'
#' Row `i` holds the fit of the window that ends on row `i`, so the first
#' `width - 1` rows are `NA`. The identity family has a closed form. The other two
#' families run iteratively reweighted least squares (IRLS) on every window at
#' once. A window with complete or quasi-complete separation cannot converge: its
#' `beta0`, `beta1` and `se` are `NA`, and one warning gives the count.
#' @param Y A numeric matrix, rows = weeks in time order, columns = draws.
#' @param width The window width in rows, at least 2.
#' @param family `"identity"` is ordinary least squares. `"quasipoisson"` is a log
#'   link and `"binomial"` a logit link, and for those `beta1` is on the link
#'   scale.
#' @param prior_weights The binomial denominators, a matrix the shape of `Y` or
#'   with one column. Only `family = "binomial"` takes it, and it needs it.
#' @param tol The iteration stops when no coefficient moves more than `tol`.
#' @param maxit The most iterations. A window that still moves more than `tol`
#'   did not converge.
#' @returns A list of four matrices, each the shape of `Y`: `beta0`, `beta1`,
#'   `se` and `converged`. `se` is the standard error of `beta1`, a Wald
#'   standard error under IRLS. The logical `converged` is `NA` on the first
#'   `width - 1` rows.
#' @section One deliberate difference from glm:
#' The function agrees with `stats::glm()` except on an all-zero window. There it
#' returns `NA`, and `stats::glm()` returns a slope of 0. `stats::glm()` stops on
#' the relative change in deviance, which is 0 from the first step. This function
#' stops on the coefficient step, which never settles, because the intercept goes
#' to `-Inf`. An all-zero window identifies no slope, and `NA` says so.
#' @family short-term trend functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 5.
#' @examples
#' # 10 weeks x 4 draws, all rising at a true slope of 2 per week
#' set.seed(1)
#' Y <- matrix(rep(1:10, 4) * 2 + rnorm(40), nrow = 10)
#'
#' rs <- rolling_slope_matrix(Y, width = 4)
#'
#' # the first three rows have no complete window, so they are NA
#' head(rs$beta1, 3)
#'
#' # the later rows find the slope, one estimate per draw
#' round(rs$beta1[8:10, ], 2)
#'
#' # `se` is the OLS standard error of the slope
#' round(rs$se[10, ], 2)
#'
#' # a log link: counts that rise by 0.2 per week on the log scale
#' N <- matrix(rpois(40, rep(exp(1 + 0.2 * 1:10), 4)), nrow = 10)
#' round(rolling_slope_matrix(N, width = 4, family = "quasipoisson")$beta1[10, ], 2)
#' @export
rolling_slope_matrix <- function(
  Y,
  width,
  family = c("identity", "quasipoisson", "binomial"),
  prior_weights = NULL,
  tol = 1e-10,
  maxit = 25L
) {
  stopifnot(is.matrix(Y), width >= 2)
  family <- match.arg(family)
  if (!is.null(prior_weights) && family != "binomial") {
    stop("`prior_weights` is only used by family = 'binomial'", call. = FALSE)
  }
  if (family != "identity") {
    return(rolling_irls_slope(Y, width, family, prior_weights, tol, maxit))
  }

  n <- width
  t_bar <- (n + 1) / 2
  SS_t <- n * (n^2 - 1) / 12
  W <- nrow(Y)
  D <- ncol(Y)
  z <- matrix(0, 1, D)

  CY0 <- rbind(z, matrixStats::colCumsums(Y)) # (W+1) x D, CY0[k]=sum Y[1..k-1]
  CY20 <- rbind(z, matrixStats::colCumsums(Y * Y))
  roll <- function(C0, w) {
    # width-w rolling sum; NA first w-1 rows
    out <- matrix(NA_real_, W, D)
    out[w:W, ] <- C0[(w + 1):(W + 1), , drop = FALSE] -
      C0[1:(W - w + 1), , drop = FALSE]
    return(out)
  }
  Sx <- roll(CY0, n)
  Sx2 <- roll(CY20, n)
  Stx <- Reduce(`+`, lapply(1:n, function(w) roll(CY0, w))) # sum_{w=1}^n rollsum_w

  beta1 <- (Stx - t_bar * Sx) / SS_t
  beta0 <- Sx / n - beta1 * t_bar
  RSS <- pmax(Sx2 - Sx^2 / n - beta1^2 * SS_t, 0)
  se <- sqrt(RSS / ((n - 2) * SS_t))
  # The closed form solves each complete window in one step, so there is no
  # iteration to fail. `converged` exists so that the return shape does not
  # depend on the family.
  converged <- matrix(NA, W, D)
  converged[n:W, ] <- TRUE
  return(list(beta0 = beta0, beta1 = beta1, se = se, converged = converged))
}

# The response contract for a link family. Returns `prior_weights` recycled to
# one column per draw, so the caller holds a matrix of the same shape as `Y`.
irls_check_response <- function(Y, prior_weights, binom, W, D) {
  if (!binom) {
    if (any(Y < 0, na.rm = TRUE)) {
      stop("family = 'quasipoisson' needs a non-negative `Y`", call. = FALSE)
    }
    return(prior_weights)
  }
  if (is.null(prior_weights)) {
    stop(
      "family = 'binomial' needs `prior_weights` (the binomial denominator)",
      call. = FALSE
    )
  }
  stopifnot(is.matrix(prior_weights), nrow(prior_weights) == W)
  if (ncol(prior_weights) == 1L && D > 1L) {
    prior_weights <- prior_weights[, rep(1L, D), drop = FALSE]
  }
  if (ncol(prior_weights) != D) {
    stop(
      "`prior_weights` must have 1 column, or as many columns as `Y`",
      call. = FALSE
    )
  }
  if (any(Y < 0 | Y > 1, na.rm = TRUE)) {
    stop(
      "family = 'binomial' needs `Y` on the response scale: 0 <= y <= 1",
      call. = FALSE
    )
  }
  return(prior_weights)
}

# One IRLS step for one lag: the working weight `w` and the working response
# `z`. `eta` is NULL on the first iteration, where the start values are glm's
# own `mustart`. `m` is the binomial denominator, NULL under a log link.
irls_working <- function(y, m, eta, binom) {
  if (is.null(eta)) {
    mu <- if (binom) (m * y + 0.5) / (m + 1) else y + 0.1
    eta <- if (binom) log(mu / (1 - mu)) else log(mu)
  } else {
    mu <- if (binom) 1 / (1 + exp(-eta)) else exp(eta)
  }
  if (binom) {
    v <- mu * (1 - mu)
    return(list(w = m * v, z = eta + (y - mu) / v))
  }
  return(list(w = mu, z = eta + (y - mu) / mu))
}

# Wald standard error at the converged coefficients: sqrt(phi * (X'WX)^-1_22),
# and (X'WX)^-1_22 is Sw / det. The quasi-Poisson dispersion is the Pearson
# statistic over width - 2; the binomial family fixes it at 1, as stats::glm
# does.
irls_wald_se <- function(b0, b1, tt, Ylag, Mlag, binom, n, D, n_rows) {
  Sw <- Swt <- Swt2 <- chi <- matrix(0, n_rows, D)
  for (j in seq_len(n)) {
    eta <- b0 + b1 * tt[j]
    mu <- if (binom) 1 / (1 + exp(-eta)) else exp(eta)
    if (binom) {
      w <- Mlag[[j]] * mu * (1 - mu)
    } else {
      w <- mu
      chi <- chi + (Ylag[[j]] - mu)^2 / mu
    }
    Sw <- Sw + w
    Swt <- Swt + w * tt[j]
    Swt2 <- Swt2 + w * tt[j]^2
  }
  phi <- if (binom) 1 else chi / (n - 2)
  return(sqrt(phi * Sw / (Sw * Swt2 - Swt^2)))
}

# IRLS on the link scale, one iteration at a time across every window and every
# draw. `Ylag[[j]]` holds the rows that sit at local time `tt[j]` in their
# window. A window sum is therefore an accumulation over j, not a rolling sum
# over rows. The start values are glm's own `mustart`, which depends on the row
# alone, so the first iteration reproduces the first step of stats::glm.fit.
rolling_irls_slope <- function(Y, width, family, prior_weights, tol, maxit) {
  n <- width
  W <- nrow(Y)
  D <- ncol(Y)
  blank <- matrix(NA_real_, W, D)
  if (W < n) {
    return(list(
      beta0 = blank,
      beta1 = blank,
      se = blank,
      converged = matrix(NA, W, D)
    ))
  }

  binom <- family == "binomial"
  prior_weights <- irls_check_response(Y, prior_weights, binom, W, D)

  rows <- n:W # the last row of each complete window
  tt <- n:1 # local time of lag j-1, for j = 1..n
  Ylag <- lapply(seq_len(n), function(j) Y[rows - (j - 1L), , drop = FALSE])
  Mlag <- if (binom) {
    lapply(seq_len(n), function(j) {
      return(prior_weights[rows - (j - 1L), , drop = FALSE])
    })
  }

  b0 <- b1 <- matrix(Inf, length(rows), D)
  step <- matrix(NA_real_, length(rows), D)
  it <- 0L
  for (it in seq_len(maxit)) {
    Sw <- Swt <- Swt2 <- Swz <- Swtz <- matrix(0, length(rows), D)
    for (j in seq_len(n)) {
      wz <- irls_working(
        Ylag[[j]],
        if (binom) Mlag[[j]] else NULL,
        if (it == 1L) NULL else b0 + b1 * tt[j],
        binom
      )
      w <- wz$w
      z <- wz$z
      Sw <- Sw + w
      Swt <- Swt + w * tt[j]
      Swt2 <- Swt2 + w * tt[j]^2
      Swz <- Swz + w * z
      Swtz <- Swtz + w * tt[j] * z
    }
    det <- Sw * Swt2 - Swt^2
    new1 <- (Sw * Swtz - Swt * Swz) / det
    new0 <- (Swt2 * Swz - Swt * Swtz) / det
    # `step` is per window, `delta` is the whole batch. The loop stops on
    # `delta`, and `step` at the last iteration says which windows got there.
    # A converged window sits at its own fixed point while the batch runs on,
    # so its step stays at machine precision.
    step <- pmax(abs(new1 - b1), abs(new0 - b0))
    delta <- suppressWarnings(max(step, na.rm = TRUE))
    b1 <- new1
    b0 <- new0
    if (delta < tol) break
  }
  ok <- !is.na(step) & step < tol

  # Wald standard error at the converged coefficients: sqrt(phi * (X'WX)^-1_22),
  # and (X'WX)^-1_22 is Sw / det. The quasi-Poisson dispersion is the Pearson
  # statistic over width - 2; the binomial family fixes it at 1, as stats::glm
  # does.
  se <- irls_wald_se(b0, b1, tt, Ylag, Mlag, binom, n, D, length(rows))

  # A non-convergent window is a separated one. Its last iterate is a finite
  # number of no meaning: 25.19 on the logit scale reaches $draws as 1.1e13
  # percent per week. `is.finite()` cannot catch that. A missing slope is the
  # honest answer, so drop it and say how many were dropped. `beta0` goes with
  # it: a lone intercept beside a missing slope reads as a fitted level, and it
  # is the same meaningless iterate.
  b0[!ok] <- NA_real_
  b1[!ok] <- NA_real_
  se[!ok] <- NA_real_
  n_bad <- sum(!ok)
  if (n_bad > 0L) {
    # `it` is the iteration the batch stopped on, which is not always `maxit`.
    # `delta` drops a missing window with na.rm, so a batch holding one can
    # settle early while that window stays unconverged.
    warning(
      sprintf(
        paste0(
          "rolling_slope_matrix: IRLS did not converge in %d of %d window ",
          "fits after %d iterations (maxit = %d). `beta0`, `beta1` and `se` ",
          "are NA there. Check those windows for separation or for a missing ",
          "value."
        ),
        n_bad,
        length(ok),
        it,
        maxit
      ),
      call. = FALSE
    )
  }

  pad <- function(M, fill = NA_real_) {
    out <- matrix(fill, W, D)
    out[rows, ] <- M
    return(out)
  }
  return(list(
    beta0 = pad(b0),
    beta1 = pad(b1),
    se = pad(se),
    converged = pad(ok, NA)
  ))
}

# The binomial denominator is a measure name in $draws, matching
# ens_add_rate(). It is drawn like everything else, so it carries its own
# uncertainty column by column.
stt_prior_weights <- function(x, family, denominator) {
  if (family != "binomial") {
    if (!is.null(denominator)) {
      stop("`denominator` is only used by family = 'binomial'", call. = FALSE)
    }
    return(NULL)
  }
  if (is.null(denominator)) {
    stop(
      paste0(
        "family = 'binomial' needs `denominator`, the $draws measure holding ",
        "the binomial denominator"
      ),
      call. = FALSE
    )
  }
  if (!denominator %in% names(x$draws)) {
    stop(
      sprintf(
        "denominator '%s' not in $draws (have: %s)",
        denominator,
        paste(names(x$draws), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  return(x$draws[[denominator]])
}

# The reference distribution for the slope's own sampling error, and its
# degrees of freedom where it has any.
#
# "auto" reads the dispersion. Identity and quasi-Poisson both estimate one
# from width - 2 residual degrees of freedom, which is the case summary.glm()
# refers to a t. The binomial family fixes it at 1, so a normal is the right
# reference there.
#
# At width 2 those two families have no residual degrees of freedom, so `se` is
# NaN under identity and Inf under quasi-Poisson, and the growth rate reaches
# $draws missing or as a random -100 percent. No `error_reference` escapes
# that: the defect is in `se`, not in the reference.
stt_error_reference <- function(family, error_reference, width) {
  if (family != "binomial" && width < 3) {
    stop(
      sprintf(
        paste0(
          "the slope error needs trend_isoyearweeks >= 3 under family = ",
          "'%s'. That family estimates a dispersion from width - 2 residual ",
          "degrees of freedom, so `se` is not defined at width 2. Only ",
          "family = 'binomial' fixes the dispersion at 1 and accepts width 2."
        ),
        family
      ),
      call. = FALSE
    )
  }
  reference <- if (error_reference != "auto") {
    error_reference
  } else if (family == "binomial") {
    "normal"
  } else {
    "t"
  }
  if (reference != "t") {
    return(list(reference = reference, df = NA_real_))
  }
  df <- width - 2
  if (df < 1) {
    stop(
      paste0(
        "the slope error needs trend_isoyearweeks >= 3 under ",
        "error_reference = 't'. A t reference needs at least 1 degree of ",
        "freedom."
      ),
      call. = FALSE
    )
  }
  return(list(reference = reference, df = df))
}

#' @rdname short_term_trend
#' @method short_term_trend csfmt_ensemble_v3
#' @section The csfmt_ensemble_v3 method:
#' In every draw, the method fits a line to the window of `trend_isoyearweeks`
#' weeks that ends on each week, with [rolling_slope_matrix()]. The first
#' `trend_isoyearweeks - 1` weeks of each series get `NA`.
#'
#' It then adds the sampling error of the slope to each draw, `beta1 + se * e`,
#' with `e` from the distribution that `error_reference` names. So a settled week,
#' with the same count in every draw, still gets an interval. The method returns
#' no increasing label: choose your own cut-off on the share of draws with a
#' positive slope.
#' @param measure The draw matrix to fit the trend to.
#' @param trend_isoyearweeks The width of the rolling window, in weeks. The
#'   ensemble method needs at least 3, or 2 with `family = "binomial"`. The v1
#'   method needs at least 2.
#' @param n_sim The number of draws to use when the ensemble has one draw, as the
#'   output of [nowcast_passthrough_to_ensemble_v1()] has.
#' @param family `"identity"` is ordinary least squares, with the growth rate
#'   `100 * beta1 / Y`. `"quasipoisson"` is a log link, and `"binomial"` a logit
#'   link that needs `denominator`. For those two, `beta1` is on the link scale.
#'   The growth rate is then `100 * (exp(beta1) - 1)`, a percent change per
#'   week, in the odds under `"binomial"`. A zero count needs no offset.
#' @param denominator For `csfmt_rts_data_v1`, an optional denominator column.
#'   For `csfmt_ensemble_v3`, the draw matrix of the binomial denominator, which
#'   `family = "binomial"` needs and the other families reject. `measure` MUST
#'   then be a proportion.
#' @param error_reference The distribution of the slope error. `"auto"` gives
#'   `"identity"` and `"quasipoisson"` a t on `trend_isoyearweeks - 2` degrees of
#'   freedom, the residual degrees of freedom of their dispersion. It gives
#'   `"binomial"` a normal. At width 3 that t is a Cauchy, with heavy tails. Use
#'   `"normal"` to match `stats::confint()`, which profiles the deviance against
#'   an asymptotic chi-squared.
#' @returns The ensemble method returns `x` with the draw matrices
#'   `<measure>_trend_beta1`, the slope per week, and `<measure>_trend_gr`, the
#'   growth rate. It adds `<measure>_trend_increasing_pr`, the share of draws with
#'   a positive slope, to `$data` by reference, so the input ensemble gets it too.
#' @export
short_term_trend.csfmt_ensemble_v3 <- function(
  x,
  measure,
  trend_isoyearweeks = 3,
  n_sim = 1000L,
  family = c("identity", "quasipoisson", "binomial"),
  denominator = NULL,
  error_reference = c("auto", "normal", "t"),
  ...
) {
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  # `propagate_slope_error` was removed. Without the guard it would land in
  # `...` and be silently ignored, so a caller who had turned it off would get
  # propagated numbers and no notice.
  if ("propagate_slope_error" %in% names(list(...))) {
    stop(
      paste0(
        "`propagate_slope_error` was removed. The slope's own sampling error ",
        "is always propagated now, because P(increasing) without it is a sign ",
        "test rather than a probability. There is no way to switch it off."
      ),
      call. = FALSE
    )
  }
  family <- match.arg(family)
  error_reference <- match.arg(error_reference)
  if (!measure %in% names(x$draws)) {
    stop(
      sprintf(
        "measure '%s' not in $draws (have: %s)",
        measure,
        paste(names(x$draws), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  width <- trend_isoyearweeks
  Y <- x$draws[[measure]]

  # The binomial denominator is a measure name in $draws, matching
  # ens_add_rate(). It is drawn like everything else, so it carries its own
  # uncertainty column by column. A single-column denominator is recycled
  # across the draws of `measure`.
  prior_weights <- stt_prior_weights(x, family, denominator)
  rs <- rolling_slope_matrix(
    Y,
    width,
    family = family,
    prior_weights = prior_weights
  )

  # seam mask: windows that would straddle a series boundary
  invalid <- x$data$time_series_internal_id < width
  rs$beta1[invalid, ] <- NA_real_
  rs$beta0[invalid, ] <- NA_real_
  rs$se[invalid, ] <- NA_real_

  # The slope's own sampling error, always. Two things are uncertain and both
  # belong in the draws: the LEVEL, which the incoming ensemble already carries,
  # and the LINE fitted through those levels, which is this. P(increasing)
  # without the second is a sign test on the point slope wearing the name of a
  # probability, and a threshold like `> 0.975` then does nothing.
  beta1 <- rs$beta1
  # "auto" reads the dispersion. Identity and quasi-Poisson both estimate one
  # from width - 2 residual degrees of freedom, which is the case
  # summary.glm() refers to a t. The binomial family fixes it at 1, so a
  # normal is the right reference there.
  #
  # At width 2 identity and quasi-Poisson have no residual degrees of freedom,
  # so `se` is NaN under identity and Inf under quasi-Poisson. No
  # `error_reference` escapes that: the defect is in `se`, not in the
  # reference. stt_error_reference() therefore errors, and a two-point trend is
  # unavailable for those two families. The binomial family fixes the
  # dispersion at 1 and accepts width 2.
  ref <- stt_error_reference(family, error_reference, width)
  reference <- ref$reference
  df <- ref$df
  se <- rs$se
  # A passthrough ensemble has a single draw, so there is no draw axis to carry
  # the slope's uncertainty: perturbing one column once still leaves one column,
  # and P(increasing) stays a bare sign test. Widen the trend's own draw axis --
  # the count is observed, but its TREND is estimated. $draws matrices are
  # allowed to differ in width; ens_collapse quantiles each one independently.
  if (ncol(beta1) == 1L && n_sim > 1L) {
    rep1 <- rep(1L, n_sim)
    beta1 <- beta1[, rep1, drop = FALSE]
    se <- se[, rep1, drop = FALSE]
    Y <- Y[, rep1, drop = FALSE]
  }
  # The slope's sampling distribution is beta1_hat + se * reference.
  # WARNING: at the default width of 3 a t reference is t_1, a Cauchy. It has
  # no finite variance, so the growth-rate quantiles get heavy tails. Widen the
  # window, or set error_reference = "normal", which forces a normal on every
  # family.
  err <- if (reference == "t") {
    stats::rt(length(beta1), df = df)
  } else {
    stats::rnorm(length(beta1))
  }
  beta1 <- beta1 + se * matrix(err, nrow(beta1), ncol(beta1))

  # growth rate per draw. Identity: gr_pr100 = 100 * slope / level. Log or logit
  # link: the slope IS a growth rate on the link scale, so exp(beta1) - 1 is the
  # per-week relative change and needs no level to divide by.
  gr <- if (family == "identity") 100 * beta1 / Y else 100 * (exp(beta1) - 1)
  gr[!is.finite(gr)] <- NA_real_

  x$draws[[csfmt_var(measure, role = "trend", suffix = "_beta1")]] <- beta1
  x$draws[[csfmt_var(measure, role = "trend", suffix = "_gr")]] <- gr

  # P(increasing) = fraction of draws with a positive slope (a point column, not
  # a draw matrix, since it is already a reduction over the draw axis).
  # The slope error is always in `beta1` by now, so this is a probability
  # rather than a sign test. It was the latter until the error became
  # mandatory, and a `> 0.975` threshold on it then did nothing.
  inc <- rowMeans(beta1 > 0, na.rm = TRUE)
  inc[is.nan(inc)] <- NA_real_
  # data.table::set(), NOT `[[<-`. Base assignment copies the table and breaks its
  # self-reference, so the NEXT stage that uses `:=` on $data emits data.table's
  # "shallow copy was taken" advisory. It fires in the canonical order
  # rate -> trend -> mem -> hlm, i.e. in every production pipeline that runs a
  # trend before another ensemble stage.
  data.table::set(
    x$data,
    j = csfmt_var(measure, role = "trend", suffix = "_increasing_pr"),
    value = inc
  )

  return(validate_ensemble(x))
}
