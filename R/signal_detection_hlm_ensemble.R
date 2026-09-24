# Historical-limits signal detection (HLM) on a csfmt_ensemble_v3.
#
# Same two-part shape as mem_thresholds_v1: estimate the seasonal baseline from the
# POINT history (same calendar week in prior years, +-1 week), derive the upper
# limit qnorm(0.995, baseline_mean, baseline_sd), then CLASSIFY every DRAW against
# that limit -> an ordinal status code matrix (1 = null, 2 = high). Weeks without
# a full baseline get NA. Runs before collapse so nowcast uncertainty propagates
# into the exceedance probability.

#' @method signal_detection_hlm csfmt_ensemble_v3
#' @rdname signal_detection_hlm
#' @section The csfmt_ensemble_v3 method:
#' The baseline uses the median of the draws of each earlier week. A draw at or
#' above the limit is `high`, and otherwise `null`. After [ens_collapse()],
#' `<measure>_hlmstatus_prob_high` is the share of draws at or above the limit.
#' That share describes the nowcast uncertainty. It is not a p-value, a posterior
#' probability or a false-alarm rate.
#' @param measure The draw matrix to compare with the limit.
#' @returns The ensemble method returns `x` with a draw matrix
#'   `<measure>_hlmstatus`: 1 for `null`, 2 for `high`, and `NA` with no limit,
#'   with a `levels` attribute. It adds `hlm_threshold`, the limit, to `$data` by
#'   reference, so the input ensemble gets it too.
#' @export
signal_detection_hlm.csfmt_ensemble_v3 <- function(
  x,
  measure,
  baseline_isoyears = 5,
  ...
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  hlm_threshold <- lag <- point <- time_series_id <- weeks <- years <- NULL
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  if (!measure %in% names(x$draws)) {
    stop(sprintf("measure '%s' not in $draws", measure), call. = FALSE)
  }

  Y <- x$draws[[measure]]
  d <- data.table::data.table(
    point = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = x$data$time_series_id
  )

  # baseline = same week in prior years, +-1 week
  baseline <- data.table::CJ(weeks = -1:1, years = seq_len(baseline_isoyears))
  baseline[, lag := years * 52 + weeks]
  lagcols <- paste0(".bl", seq_len(nrow(baseline)))
  for (i in seq_len(nrow(baseline))) {
    d[,
      (lagcols[i]) := data.table::shift(point, n = baseline$lag[i]),
      by = time_series_id
    ]
  }

  bmat <- as.matrix(d[, lagcols, with = FALSE])
  bmean <- row_mean(bmat) # NA if any baseline week missing
  bsd <- row_sd(bmat)
  thr <- stats::qnorm(0.995, bmean, bsd)

  x$data[, hlm_threshold := thr]
  code <- 1L + (Y >= thr) # 1 null, 2 high; NA where no baseline
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- c("null", "high")
  x$draws[[csfmt_var(measure, role = "hlmstatus")]] <- code

  return(validate_ensemble(x))
}
