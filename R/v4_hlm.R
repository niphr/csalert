# signal_detection_hlm_v4: a copy of signal_detection_hlm.csfmt_ensemble_v3 on
# the v4 format. It finds the historical limit from the median of the draws,
# and compares every draw with it.

# The levels of the HLM status, coded 1 and 2.
.V4_HLM_LEVELS <- c("null", "high")

#' Flag the draws of a csfmt_ensemble_v4 above a historical limit
#'
#' @description
#' Compares every draw of `measure` with the historical limit, the 99.5%
#' quantile of a normal fitted to the same weeks in earlier years. The method
#' is that of [signal_detection_hlm()] for a `csfmt_ensemble_v3`, and the
#' values are identical.
#'
#' @details
#' The baseline of a week uses the median of the draws of each earlier week.
#' It holds the medians 52, 104, and so on up to `52 * baseline_isoyears` rows
#' back in the same series, each with its two neighbours. The limit is
#' `qnorm(0.995, mean, sd)` of those values. A week that lacks any of them, or
#' has an `NA` in them, gets no limit. A year back is 52 rows, so across a
#' 53-week ISO year the baseline is one week off.
#'
#' Each series MUST have one row per ISO week, from its first week to its last.
#' A week with no count MUST be a row with `NA`. The function stops on a
#' missing or repeated week, as [short_term_trend_v4()] does.
#'
#' A draw above the limit is `high`, and otherwise `null`, as in v1. A draw with
#' no limit, or an `NA` draw, gets `NA`. The share of draws at a level
#' describes the nowcast uncertainty. It is not a p-value, a posterior
#' probability or a false-alarm rate.
#'
#' The function draws no random numbers.
#' The function takes no `...`, so a misspelt argument is an error.
#' @param x The `csfmt_ensemble_v4`, full or compressed.
#' @param measure The name of the draw matrix to compare with the limit. It
#'   MUST NOT end in a reserved suffix.
#' @param baseline_isoyears The number of earlier years in the baseline.
#' @returns `x` with the new draw matrix `<measure>_hlm`, which holds 1 for
#'   `null`, 2 for `high` and `NA` with no limit, with a `levels` attribute. It
#'   adds these columns to `$data`:
#'   - `<measure>_hlm_thr`: the limit.
#'   - `<measure>_hlm_prob_null` and `<measure>_hlm_prob_high`: the share of
#'     the draws at each level, which is `NA` when every draw is `NA`.
#'
#'   The shares give every ordinal percentile of the level codes, so the step
#'   writes no percentile column.
#'
#'   Each new name MUST be at most 63 bytes. A rerun on the same `measure`
#'   replaces the draw matrix and the columns. The input `x` does not change.
#' @family v4 functions
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' iyw <- w[match("2017-01", w) + 0:319]
#' set.seed(1)
#' ens <- csfmt_ensemble_v4(
#'   data.table::data.table(location_code = "nation", isoyearweek = iyw),
#'   id_cols = "location_code",
#'   draws = list(cases = matrix(rpois(320 * 100, 50), nrow = 320))
#' )
#' ens <- signal_detection_hlm_v4(ens, measure = "cases")
#' tail(ens$data[, .(isoyearweek, cases_hlm_thr, cases_hlm_prob_high)], 3)
#' @export
signal_detection_hlm_v4 <- function(x, measure, baseline_isoyears = 5) {
  .v4_validate_ensemble(x)
  .v4_check_draw_measure(x, measure)
  nm <- .v4_hlm_names(measure)
  .v4_check_names(unlist(nm, use.names = FALSE))
  # The baseline counts back 52 rows a year, so a missing week would shift it.
  .v4_check_weeks(x)

  Y <- .v4_draws(x, measure)
  thr <- .v4_hlm_threshold(
    Y,
    series = x$data$time_series_id,
    baseline_isoyears = baseline_isoyears
  )
  # 1 for null and 2 for high. NA where the week has no limit.
  code <- 1L + (Y > thr)
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- .V4_HLM_LEVELS

  d <- data.table::copy(x$data)
  d[, (nm$thr) := thr]
  .v4_collapse_status_into(d, nm$status, code, .V4_HLM_LEVELS)
  x$data <- d
  x$draws[[nm$status]] <- code
  .v4_validate_ensemble(x)
  return(x)
}

# The new names of an HLM step on `measure`. The caller checks them with
# .v4_check_names().
.v4_hlm_names <- function(measure) {
  status <- paste0(measure, "_hlm")
  return(list(
    status = status,
    thr = paste0(status, "_thr"),
    summary = .v4_status_names(status, .V4_HLM_LEVELS)
  ))
}

# The historical limit of each row of `Y`. The baseline holds the row medians
# of the same series 52 * (1:baseline_isoyears) rows back, and the rows on
# each side of them.
.v4_hlm_threshold <- function(Y, series, baseline_isoyears) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  lag <- point <- time_series_id <- weeks <- years <- NULL
  d <- data.table::data.table(
    point = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = series
  )
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
  return(stats::qnorm(0.995, .v4_row_mean(bmat), .v4_row_sd(bmat)))
}
