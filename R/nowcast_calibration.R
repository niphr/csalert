# nowcast_estimate_calibration_v1 / nowcast_apply_calibration_v1: turn a backtest into a
# per-group interval-scaling correction, and apply it.
#
#   engine -> backtest -> estimate_calibration -> apply_calibration
#
# Method: from past nowcasts vs realized truth, for each group (default horizon)
# compute the multiplier `factor` = the empirical `level`-quantile of the scaled
# residual |truth - median| / halfwidth, where halfwidth = (hi - lo) / 2. Scaling
# every quantile's distance from the median by that factor makes the central
# `level` interval cover `level` of the BACKTEST sample. factor > 1 widens,
# factor < 1 narrows. Estimate on PAST backtests and apply to the CURRENT nowcast
# (a natural temporal hold-out).
#
# LIMITS -- read these before treating the output as a coverage guarantee:
#   - This is NOT split conformal and carries no finite-sample coverage
#     guarantee. It uses the ordinary type-7 empirical quantile of the residuals,
#     not the ceiling((n+1)*level)-th order statistic that a conformal argument
#     requires.
#   - The residual |truth - med| / halfwidth is a two-sided, symmetric summary. It
#     is only faithful for intervals roughly symmetric about the median; for a
#     skewed predictive distribution it mixes the two tails together.
#   - Coverage on the backtest is in-sample for the factor. It says what WOULD
#     have happened on those weeks; it does not certify future coverage, and the
#     exchangeability it would need does not hold across a changing reporting
#     regime.

# nearest available quantile_level to a target probability (robust to float repr)
.nearest_q <- function(levels, p) levels[which.min(abs(levels - p))]

#' Estimate a nowcast calibration from a backtest
#'
#' Learns a per-group interval-scaling correction from past nowcasts scored
#' against settled truth. See [nowcast_apply_calibration_v1] to use it.
#'
#' This is an empirical rescaling, not split conformal. It takes the ordinary
#' type-7 quantile of the scaled residuals, rather than the conformal order
#' statistic. It summarises both tails with one symmetric distance from the
#' median. It therefore carries NO finite-sample coverage guarantee. Read
#' `coverage_raw` as "what this engine did on these replayed weeks", not as a
#' property of the engine.
#' @param backtest Long quantile nowcasts (from [nowcast_backtest]): `reference`,
#'   the `by` column(s), `quantile_level`, `predicted`.
#' @param truth Settled totals (from [nowcast_truth]): `reference`, `truth`.
#' @param level Central interval level to calibrate on (default 0.9).
#' @param by Grouping column(s) the factor varies over (default "horizon").
#' @returns A `nowcast_calibration`: per-group raw coverage + scale `factor`.
#' @family nowcast calibration functions
#' @seealso Neither package vignette covers calibration. The example below is its
#'   only worked demonstration.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' i <- match("2023-01", w)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[isoyearweek_reporting <= w[i + 39]]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' method <- function(x) nowcast_quasipoisson_v1(x, max_delay = 3, n_sim = 200)
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay = 3, as_of_weeks = w[i + 20:38], horizons = 0:1, seed = 1
#' )
#'
#' # `coverage_raw` is what happened on these 19 replayed weeks, and `factor` is
#' # what would have made the 90% interval cover 90% of them. Here coverage is
#' # above nominal and the factor is below 1, i.e. narrower intervals would have
#' # sufficed ON THIS SAMPLE. With n of about 19 that is far too little evidence
#' # to call the engine over-dispersed in general; treat it as a flag to look
#' # into, not a verdict.
#' nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay = 3))
#' @export
nowcast_estimate_calibration_v1 <- function(
  backtest,
  truth,
  level = 0.9,
  by = "horizon"
) {
  d <- merge(
    data.table::as.data.table(backtest),
    data.table::as.data.table(truth),
    by = "reference"
  )
  qlevs <- sort(unique(d$quantile_level))
  lo_q <- .nearest_q(qlevs, (1 - level) / 2)
  hi_q <- .nearest_q(qlevs, 1 - (1 - level) / 2)
  med_q <- .nearest_q(qlevs, 0.5)
  key <- unique(c(by, "reference"))

  piv <- d[quantile_level == med_q, .(med = predicted[1]), by = key]
  piv <- merge(
    piv,
    d[quantile_level == lo_q, .(lo = predicted[1]), by = key],
    by = key
  )
  piv <- merge(
    piv,
    d[quantile_level == hi_q, .(hi = predicted[1]), by = key],
    by = key
  )
  piv <- merge(piv, unique(d[, c(key, "truth"), with = FALSE]), by = key)
  piv[, halfwidth := pmax((hi - lo) / 2, 1e-9)]
  piv[, r := abs(truth - med) / halfwidth]
  piv[, covered := truth >= lo & truth <= hi]

  tab <- piv[,
    .(
      n = .N,
      coverage_raw = round(mean(covered), 3),
      factor = round(
        as.numeric(stats::quantile(
          r,
          probs = level,
          names = FALSE,
          na.rm = TRUE,
          type = 7
        )),
        3
      )
    ),
    by = by
  ][order(get(by[1]))]
  structure(
    list(level = level, by = by, table = tab[]),
    class = "nowcast_calibration"
  )
}

#' Print a `nowcast_calibration`
#'
#' Shows the nominal interval level, the grouping, and the per-group calibration
#' factor table (factor > 1 widens an under-dispersed engine; < 1 narrows).
#' @param x A `nowcast_calibration` from [nowcast_estimate_calibration_v1].
#' @param ... Ignored (for S3 consistency).
#' @returns `x`, invisibly.
#' @family nowcast calibration functions
#' @seealso Neither package vignette covers calibration; see the example on
#'   \code{\link{nowcast_estimate_calibration_v1}}, which prints its result with
#'   this method.
#' @export
print.nowcast_calibration <- function(x, ...) {
  cat(sprintf(
    "<nowcast_calibration>  %g%% interval, by %s\n",
    100 * x$level,
    paste(x$by, collapse = " + ")
  ))
  cat("  factor > 1 widens (under-dispersed); < 1 narrows (over-dispersed)\n")
  print(x$table)
  invisible(x)
}

#' Apply a nowcast calibration to quantile predictions
#'
#' Rescales each quantile by moving it away from (or toward) the median by the
#' learned per-group `factor`. By construction the rescaled central interval
#' covers `level` of the BACKTEST the factor was learned on; that is not a
#' guarantee about future weeks, and the median is left unchanged. Groups with no
#' learned factor (e.g. an unseen horizon) pass through unchanged.
#' @param x Long quantile predictions (`reference`, the calibration's `by`
#'   column(s), `quantile_level`, `predicted`) -- e.g. a fresh [nowcast_backtest]
#'   output or a melted collapse.
#' @param calibration A `nowcast_calibration` from [nowcast_estimate_calibration_v1].
#' @returns `x` with `predicted` recalibrated.
#' @family nowcast calibration functions
#' @seealso Neither package vignette covers calibration. The example below is its
#'   only worked demonstration.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' i <- match("2023-01", w)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[isoyearweek_reporting <= w[i + 39]]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' method <- function(x) nowcast_quasipoisson_v1(x, max_delay = 3, n_sim = 200)
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay = 3, as_of_weeks = w[i + 20:38], horizons = 0:1,
#'   probs = c(0.05, 0.5, 0.95), seed = 1
#' )
#' cal <- nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay = 3))
#'
#' adj <- nowcast_apply_calibration_v1(bt, cal)
#'
#' # the median is untouched; the other two quantiles move toward or away from
#' # it, so the interval width changes by the learned factor
#' width <- function(x) {
#'   x[horizon == 0, .(width = diff(range(predicted))), by = reference][1:3]
#' }
#' width(bt)
#' width(adj)
#' @export
nowcast_apply_calibration_v1 <- function(x, calibration) {
  stopifnot(inherits(calibration, "nowcast_calibration"))
  d <- data.table::as.data.table(data.table::copy(x))
  by <- calibration$by
  qlevs <- sort(unique(d$quantile_level))
  med_q <- .nearest_q(qlevs, 0.5)
  key <- unique(c(by, "reference"))

  d[, .med := predicted[quantile_level == med_q][1], by = key]
  d <- merge(
    d,
    calibration$table[, c(by, "factor"), with = FALSE],
    by = by,
    all.x = TRUE
  )
  d[is.na(factor), factor := 1] # unseen group -> identity
  d[, predicted := .med + factor * (predicted - .med)]
  d[, c(".med", "factor") := NULL]
  d[]
}
