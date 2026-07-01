# nowcast_estimate_calibration_v1 / nowcast_apply_calibration_v1: turn a backtest into a
# calibration correction and apply it, so a nowcast's intervals achieve nominal
# coverage regardless of what the engine gets wrong internally.
#
#   engine -> backtest -> estimate_calibration -> apply_calibration -> honest intervals
#
# Method: per-group conformal interval scaling. From past nowcasts vs realized
# truth, for each group (default horizon) compute the multiplier `factor` such
# that scaling every quantile's distance from the median by it makes the central
# `level` interval cover `level` of the time -- i.e. factor = the level-quantile
# of |truth - median| / halfwidth. Under-dispersed -> factor > 1 (widen);
# over-dispersed -> factor < 1 (narrow). Applying it around the median
# recalibrates all quantiles and, on exchangeable data, gives ~nominal coverage
# (split conformal). Estimate on PAST backtests and apply to the CURRENT nowcast
# (a natural temporal hold-out).

# nearest available quantile_level to a target probability (robust to float repr)
.nearest_q <- function(levels, p) levels[which.min(abs(levels - p))]

#' Estimate a nowcast calibration from a backtest
#'
#' Learns a per-group interval-scaling correction (conformal) from past nowcasts
#' scored against settled truth. See [nowcast_apply_calibration_v1] to use it.
#' @param backtest Long quantile nowcasts (from [nowcast_backtest]): `reference`,
#'   the `by` column(s), `quantile_level`, `predicted`.
#' @param truth Settled totals (from [nowcast_truth]): `reference`, `truth`.
#' @param level Central interval level to calibrate on (default 0.9).
#' @param by Grouping column(s) the factor varies over (default "horizon").
#' @returns A `nowcast_calibration`: per-group raw coverage + scale `factor`.
#' @export
nowcast_estimate_calibration_v1 <- function(backtest, truth, level = 0.9, by = "horizon") {
  d <- merge(data.table::as.data.table(backtest),
             data.table::as.data.table(truth), by = "reference")
  qlevs <- sort(unique(d$quantile_level))
  lo_q  <- .nearest_q(qlevs, (1 - level) / 2)
  hi_q  <- .nearest_q(qlevs, 1 - (1 - level) / 2)
  med_q <- .nearest_q(qlevs, 0.5)
  key <- unique(c(by, "reference"))

  piv <- d[quantile_level == med_q, .(med = predicted[1]), by = key]
  piv <- merge(piv, d[quantile_level == lo_q, .(lo = predicted[1]), by = key], by = key)
  piv <- merge(piv, d[quantile_level == hi_q, .(hi = predicted[1]), by = key], by = key)
  piv <- merge(piv, unique(d[, c(key, "truth"), with = FALSE]), by = key)
  piv[, halfwidth := pmax((hi - lo) / 2, 1e-9)]
  piv[, r := abs(truth - med) / halfwidth]
  piv[, covered := truth >= lo & truth <= hi]

  tab <- piv[, .(n = .N,
                 coverage_raw = round(mean(covered), 3),
                 factor = round(as.numeric(stats::quantile(r, probs = level, names = FALSE,
                                                           na.rm = TRUE, type = 7)), 3)),
             by = by][order(get(by[1]))]
  structure(list(level = level, by = by, table = tab[]),
            class = "nowcast_calibration")
}

#' @export
print.nowcast_calibration <- function(x, ...) {
  cat(sprintf("<nowcast_calibration>  %g%% interval, by %s\n",
              100 * x$level, paste(x$by, collapse = " + ")))
  cat("  factor > 1 widens (under-dispersed); < 1 narrows (over-dispersed)\n")
  print(x$table)
  invisible(x)
}

#' Apply a nowcast calibration to quantile predictions
#'
#' Recalibrates each quantile by scaling its distance from the median by the
#' learned per-group `factor`, so the intervals hit nominal coverage. Groups with
#' no learned factor (e.g. an unseen horizon) pass through unchanged.
#' @param x Long quantile predictions (`reference`, the calibration's `by`
#'   column(s), `quantile_level`, `predicted`) -- e.g. a fresh [nowcast_backtest]
#'   output or a melted collapse.
#' @param calibration A `nowcast_calibration` from [nowcast_estimate_calibration_v1].
#' @returns `x` with `predicted` recalibrated.
#' @export
nowcast_apply_calibration_v1 <- function(x, calibration) {
  stopifnot(inherits(calibration, "nowcast_calibration"))
  d <- data.table::as.data.table(data.table::copy(x))
  by <- calibration$by
  qlevs <- sort(unique(d$quantile_level))
  med_q <- .nearest_q(qlevs, 0.5)
  key <- unique(c(by, "reference"))

  d[, .med := predicted[quantile_level == med_q][1], by = key]
  d <- merge(d, calibration$table[, c(by, "factor"), with = FALSE], by = by, all.x = TRUE)
  d[is.na(factor), factor := 1]                       # unseen group -> identity
  d[, predicted := .med + factor * (predicted - .med)]
  d[, c(".med", "factor") := NULL]
  d[]
}
