# Batched short-term trend on a csfmt_ensemble.
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
#' @export
rolling_slope_matrix <- function(Y, width) {
  stopifnot(is.matrix(Y), width >= 2)
  n <- width
  t_bar <- (n + 1) / 2
  SS_t  <- n * (n^2 - 1) / 12
  W <- nrow(Y); D <- ncol(Y)
  z <- matrix(0, 1, D)

  CY0  <- rbind(z, matrixStats::colCumsums(Y))      # (W+1) x D, CY0[k]=sum Y[1..k-1]
  CY20 <- rbind(z, matrixStats::colCumsums(Y * Y))
  roll <- function(C0, w) {                          # width-w rolling sum; NA first w-1 rows
    out <- matrix(NA_real_, W, D)
    out[w:W, ] <- C0[(w + 1):(W + 1), , drop = FALSE] - C0[1:(W - w + 1), , drop = FALSE]
    out
  }
  Sx  <- roll(CY0, n)
  Sx2 <- roll(CY20, n)
  Stx <- Reduce(`+`, lapply(1:n, function(w) roll(CY0, w)))   # sum_{w=1}^n rollsum_w

  beta1 <- (Stx - t_bar * Sx) / SS_t
  beta0 <- Sx / n - beta1 * t_bar
  RSS   <- pmax(Sx2 - Sx^2 / n - beta1^2 * SS_t, 0)
  se    <- sqrt(RSS / ((n - 2) * SS_t))
  list(beta0 = beta0, beta1 = beta1, se = se)
}

#' @method short_term_trend csfmt_ensemble
#' @rdname short_term_trend
#' @param measure Character: the `$draws` measure to compute the trend on.
#' @param trend_isoyearweeks Rolling window width in isoyearweeks (>= 2).
#' @export
short_term_trend.csfmt_ensemble <- function(x, measure, trend_isoyearweeks = 3, ...) {
  stopifnot(inherits(x, "csfmt_ensemble"))
  if (!measure %in% names(x$draws))
    stop(sprintf("measure '%s' not in $draws (have: %s)", measure,
                 paste(names(x$draws), collapse = ", ")))
  width <- trend_isoyearweeks
  Y <- x$draws[[measure]]
  rs <- rolling_slope_matrix(Y, width)

  # seam mask: windows that would straddle a series boundary
  invalid <- x$data$time_series_internal_id < width
  rs$beta1[invalid, ] <- NA_real_
  rs$beta0[invalid, ] <- NA_real_
  rs$se[invalid, ]    <- NA_real_

  # growth rate per draw: gr_pr100 = 100 * slope / level
  gr <- 100 * rs$beta1 / Y
  gr[!is.finite(gr)] <- NA_real_

  x$draws[[csfmt_var(measure, role = "trend", suffix = "_beta1")]] <- rs$beta1
  x$draws[[csfmt_var(measure, role = "trend", suffix = "_gr")]]    <- gr
  validate_ensemble(x)
}
