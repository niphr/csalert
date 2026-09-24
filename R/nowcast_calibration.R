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

#' Estimate an interval scaling factor from a backtest
#'
#' Measures, for each group, the factor that would have made the central `level`
#' interval of past nowcasts cover `level` of their settled truths. Use it to
#' check an engine. [nowcast_apply_calibration_v1()] applies it if you choose to.
#'
#' The factor is the type-7 `level` quantile of `|truth - median| / halfwidth`,
#' where `halfwidth` is half the width of the interval. Above 1, the intervals
#' were too narrow, and below 1 too wide.
#'
#' This is an empirical rescaling, not split conformal. It uses the type-7
#' quantile, not the order statistic that a conformal argument needs, and one
#' symmetric distance for both tails. So it carries NO finite-sample coverage
#' guarantee. `coverage_raw` is what the engine did on these replayed weeks, not a
#' property of the engine.
#' @param backtest The output of [nowcast_backtest()]. The function uses the
#'   `quantile_level` nearest to each end of the interval and to the median.
#' @param truth The output of [nowcast_truth()].
#' @param level The central interval level.
#' @param by The columns that the factor varies over.
#' @returns A `nowcast_calibration`: a list with `level`, `by` and `table`, which
#'   has the `by` columns, `n`, `coverage_raw`, the share of truths inside the
#'   interval, and `factor`.
#' @family nowcast calibration functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 2, which measures
#'   the coverage that the factor corrects.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay_days = 21,
#'   as_of_weeks = as.Date("2023-01-02") + 7 * (20:38) + 6,
#'   horizons = 0:1, seed = 1
#' )
#'
#' # The two horizons fall on opposite sides of 0.9, on 17 and 18 scored weeks.
#' # That is too little evidence to call the engine over- or under-dispersed, so
#' # read a factor as a reason to look closer, not as a verdict.
#' nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay_days = 21))
#' @export
nowcast_estimate_calibration_v1 <- function(
  backtest,
  truth,
  level = 0.9,
  by = "horizon"
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  covered <- halfwidth <- hi <- lo <- med <- predicted <- quantile_level <- r <- NULL
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
  return(structure(
    list(level = level, by = by, table = tab[]),
    class = "nowcast_calibration"
  ))
}

#' Print a `nowcast_calibration`
#'
#' Prints the interval level, the grouping columns and the table of factors.
#' @param x The `nowcast_calibration` to print.
#' @param ... Not used, but the `print()` generic has it.
#' @returns `x`, invisibly.
#' @family nowcast calibration functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 2.
#' @export
print.nowcast_calibration <- function(x, ...) {
  cat(sprintf(
    "<nowcast_calibration>  %g%% interval, by %s\n",
    100 * x$level,
    paste(x$by, collapse = " + ")
  ))
  cat("  factor > 1 widens (under-dispersed); < 1 narrows (over-dispersed)\n")
  print(x$table)
  return(invisible(x))
}

#' Rescale quantile nowcasts by a calibration factor
#'
#' Moves every quantile away from the median, or toward it, by the factor of its
#' group. The median does not move, and a group with no factor passes through.
#'
#' The rescaled interval covers about `level` of the backtest that the factor
#' came from, not exactly. The type-7 quantile interpolates, and each tail moves
#' by its own distance from the median. On future weeks there is no guarantee.
#' @param x Long quantile nowcasts with `reference`, the `by` columns,
#'   `quantile_level` and `predicted`, such as the output of [nowcast_backtest()].
#' @param calibration A `nowcast_calibration` from
#'   [nowcast_estimate_calibration_v1()].
#' @returns A copy of `x` with `predicted` rescaled.
#' @family nowcast calibration functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 2.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay_days = 21,
#'   as_of_weeks = as.Date("2023-01-02") + 7 * (20:38) + 6,
#'   horizons = 0:1, probs = c(0.05, 0.5, 0.95), seed = 1
#' )
#' cal <- nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay_days = 21))
#'
#' adj <- nowcast_apply_calibration_v1(bt, cal)
#'
#' # the median stays, and the width of the interval changes by the factor
#' width <- function(x) {
#'   x[horizon == 0, .(width = diff(range(predicted))), by = reference][1:3]
#' }
#' width(bt)
#' width(adj)
#' @export
nowcast_apply_calibration_v1 <- function(x, calibration) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  .med <- predicted <- quantile_level <- NULL
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
  return(d[])
}
