# nowcast (passthrough): csfmt_reporting_triangle_v3 -> csfmt_ensemble_v3.
#
# The passthrough engine collapses the triangle to the observed (reported-so-far)
# totals per reference week and wraps them as a degenerate single-draw ensemble --
# for indicators that should NOT be nowcast-completed. The modelling nowcast
# engines live in their own files (see nowcast_delay_ecdf_v1).
#
# THE HORIZON IS IN DAYS, because the triangle's reporting axis is a calendar
# date. qc_week_over_week_v1 keeps a horizon in WEEKS under a different name,
# max_delay_weeks, so that one name never means days here and weeks there.

#' Build an ensemble from a reporting triangle WITHOUT nowcasting (passthrough)
#'
#' Collapse the triangle to the observed (reported-so-far) totals per reference
#' week and wrap them as a degenerate single-draw ensemble. Some indicators
#' SHOULD NOT be nowcast-completed, because reporting is effectively complete or
#' the analyst chose not to model the delay. Such an indicator then flows through
#' the SAME rate/trend/MEM/collapse pipeline, with its observed values unchanged.
#' It emits the same `<measure>_nowcasted` columns as the modelling engines, here
#' equal to the observed value. All downstream code is therefore identical. The
#' single draw makes every collapsed quantile equal the observed point.
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param max_delay_days Delay horizon in DAYS: delay day 0 to
#'   `max_delay_days - 1`. It defines the contiguous reference grid.
#'   [qc_week_over_week_v1] takes `max_delay_weeks` instead, counted in WEEKS.
#'   The two names differ because the two units differ.
#' @param denominator_col Optional denominator column, carried through the same
#'   way (its observed total is also surfaced as `<denom>_observed`).
#' @returns A `csfmt_ensemble_v3` with single-column draw matrices.
#' @family nowcast engines
#' @seealso \code{vignette("pipeline", package = "csalert")} races this engine
#'   against \code{\link{nowcast_delay_ecdf_v1}} on the same triangle. That is
#'   the clearest way to see what completion buys you over the observed counts
#'   passed through unchanged.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday, then
#' # right-truncated so the newest weeks are still incomplete
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
#' ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay_days = 21)
#' ens
#'
#' # one draw only, so every collapsed quantile equals the observed total --
#' # including for the newest, still-incomplete weeks
#' r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
#' tail(r[, .(
#'   isoyearweek, original,
#'   lo = numerator_nowcasted_q05x0,
#'   med = numerator_nowcasted_q50x0,
#'   hi = numerator_nowcasted_q95x0
#' )], 3)
#' @export
nowcast_passthrough_to_ensemble_v1 <- function(
  x,
  max_delay_days,
  denominator_col = NULL
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  isoyearweek <- original <- time_series_id <- NULL
  stopifnot(inherits(x, "csfmt_reporting_triangle_v3"))
  id_cols <- attr(x, "id_cols")
  val_col <- attr(x, "value_col")
  value_cols <- c(val_col, denominator_col)
  d_tri <- data.table::as.data.table(x)

  rts_num <- reporting_triangle_matrix(x, max_delay_days, value_col = val_col)
  series_ids <- names(rts_num)

  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(
      1L,
      length(refs)
    )]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay_days, value_col = vc)
    obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
    draws[[csfmt_var(vc, role = "nowcasted")]] <- matrix(obs, ncol = 1)
    if (!identical(vc, val_col)) {
      data[, (csfmt_var(vc, role = "observed")) := obs]
    }
  }

  return(csfmt_ensemble_v3(
    data,
    id_cols = id_cols,
    time_col = "isoyearweek",
    draws = draws
  ))
}
