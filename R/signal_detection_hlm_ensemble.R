# Historical-limits signal detection (HLM) on a csfmt_ensemble_v3.
#
# Same two-part shape as mem_thresholds: estimate the seasonal baseline from the
# POINT history (same calendar week in prior years, +-1 week), derive the upper
# limit qnorm(0.995, baseline_mean, baseline_sd), then CLASSIFY every DRAW against
# that limit -> an ordinal status code matrix (1 = null, 2 = high). Weeks without
# a full baseline get NA. Runs before collapse so nowcast uncertainty propagates
# into the exceedance probability.

#' @method signal_detection_hlm csfmt_ensemble_v3
#' @rdname signal_detection_hlm
#' @param measure The `$draws` measure to detect signals on.
#' @param baseline_isoyears Years of history used for the baseline.
#' @export
signal_detection_hlm.csfmt_ensemble_v3 <- function(x, measure, baseline_isoyears = 5, ...) {
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  if (!measure %in% names(x$draws))
    stop(sprintf("measure '%s' not in $draws", measure))

  Y <- x$draws[[measure]]
  d <- data.table::data.table(
    point          = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = x$data$time_series_id
  )

  # baseline = same week in prior years, +-1 week
  baseline <- data.table::CJ(weeks = -1:1, years = seq_len(baseline_isoyears))
  baseline[, lag := years * 52 + weeks]
  lagcols <- paste0(".bl", seq_len(nrow(baseline)))
  for (i in seq_len(nrow(baseline)))
    d[, (lagcols[i]) := data.table::shift(point, n = baseline$lag[i]), by = time_series_id]

  bmat <- as.matrix(d[, lagcols, with = FALSE])
  bmean <- row_mean(bmat)                       # NA if any baseline week missing
  bsd   <- row_sd(bmat)
  thr   <- stats::qnorm(0.995, bmean, bsd)

  x$data[, hlm_threshold := thr]
  code <- 1L + (Y >= thr)                        # 1 null, 2 high; NA where no baseline
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- c("null", "high")
  x$draws[[csfmt_var(measure, role = "hlmstatus")]] <- code

  validate_ensemble(x)
}
