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

#' Rolling OLS slope over a weeks x draws matrix
#'
#' Closed-form simple linear regression of each window (length `width`, time
#' index 1..width) applied independently down every column. Returns matrices of
#' the same shape; leading `width-1` rows of each column are NA.
#' @param Y Numeric matrix, rows = time (ordered), columns = draws.
#' @param width Window width (>= 2).
#' @returns List of matrices: `beta0`, `beta1`, `se`.
#' @seealso Neither package vignette covers this function. It is the numeric
#'   kernel behind the ensemble method of \code{\link{short_term_trend}}, which
#'   is the function you normally want. Use this one when you have a bare
#'   weeks x draws matrix and no ensemble.
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
#' # later rows recover the slope, one estimate per draw
#' round(rs$beta1[8:10, ], 2)
#'
#' # `se` is the OLS standard error of that slope
#' round(rs$se[10, ], 2)
#' @export
rolling_slope_matrix <- function(Y, width) {
  stopifnot(is.matrix(Y), width >= 2)
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
    out
  }
  Sx <- roll(CY0, n)
  Sx2 <- roll(CY20, n)
  Stx <- Reduce(`+`, lapply(1:n, function(w) roll(CY0, w))) # sum_{w=1}^n rollsum_w

  beta1 <- (Stx - t_bar * Sx) / SS_t
  beta0 <- Sx / n - beta1 * t_bar
  RSS <- pmax(Sx2 - Sx^2 / n - beta1^2 * SS_t, 0)
  se <- sqrt(RSS / ((n - 2) * SS_t))
  list(beta0 = beta0, beta1 = beta1, se = se)
}

#' @method short_term_trend csfmt_ensemble_v3
#' @rdname short_term_trend
#' @param measure Character: the `$draws` measure to compute the trend on.
#' @param trend_isoyearweeks Rolling window width in isoyearweeks (>= 2).
#' @param propagate_slope_error Logical. If `TRUE`, add the OLS slope's own
#'   sampling error to each draw (`beta1 + se * t_(width-2)`) before the growth
#'   rate is formed. The trend interval then reflects the uncertainty of the
#'   slope estimate, and not only the uncertainty of the level. Defaults to
#'   `FALSE`, which keeps the published numbers unchanged. Note the degrees of
#'   freedom are `trend_isoyearweeks - 2`. At the default width of 3 that is 1, a
#'   Cauchy, so widen the window before you enable this.
#' @param n_sim Integer. Draw-axis width used for the slope-error perturbation
#'   when the incoming ensemble is degenerate. A degenerate ensemble holds a
#'   single passthrough draw, so it has no draw axis to carry the uncertainty.
#'   Ignored when the ensemble
#'   already has draws, and when `propagate_slope_error` is `FALSE`.
#' @returns The `csfmt_ensemble_v3` with per-draw short-term-trend columns added
#'   to `$draws` for `measure` (the rolling slope/level and a P(increasing)),
#'   ready for the quantile collapse.
#' @export
short_term_trend.csfmt_ensemble_v3 <- function(
  x,
  measure,
  trend_isoyearweeks = 3,
  propagate_slope_error = FALSE,
  n_sim = 1000L,
  ...
) {
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  if (!measure %in% names(x$draws)) {
    stop(sprintf(
      "measure '%s' not in $draws (have: %s)",
      measure,
      paste(names(x$draws), collapse = ", ")
    ))
  }
  width <- trend_isoyearweeks
  Y <- x$draws[[measure]]
  rs <- rolling_slope_matrix(Y, width)

  # seam mask: windows that would straddle a series boundary
  invalid <- x$data$time_series_internal_id < width
  rs$beta1[invalid, ] <- NA_real_
  rs$beta0[invalid, ] <- NA_real_
  rs$se[invalid, ] <- NA_real_

  beta1 <- rs$beta1
  if (propagate_slope_error) {
    df <- width - 2
    if (df < 1) {
      stop("propagate_slope_error needs trend_isoyearweeks >= 3")
    }
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
    # The OLS slope's sampling distribution is beta1_hat + se * t_(width-2).
    # WARNING: at the default width of 3 that is t_1, i.e. Cauchy -- no finite
    # variance, so the growth-rate quantiles get very heavy tails. Widen the
    # window before turning this on.
    beta1 <- beta1 +
      se * matrix(stats::rt(length(beta1), df = df), nrow(beta1), ncol(beta1))
  }

  # growth rate per draw: gr_pr100 = 100 * slope / level
  gr <- 100 * beta1 / Y
  gr[!is.finite(gr)] <- NA_real_

  x$draws[[csfmt_var(measure, role = "trend", suffix = "_beta1")]] <- beta1
  x$draws[[csfmt_var(measure, role = "trend", suffix = "_gr")]] <- gr

  # P(increasing) = fraction of draws with a positive slope (a point column, not
  # a draw matrix, since it is already a reduction over the draw axis).
  # NB with a single-draw (passthrough) ensemble and propagate_slope_error =
  # FALSE this is exactly 0 or 1 -- a bare positive slope reads as certainty.
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

  validate_ensemble(x)
}
