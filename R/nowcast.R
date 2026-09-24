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

#' Build an ensemble from a reporting triangle with no nowcast
#'
#' Returns the counts reported so far as an ensemble with one draw. Use it for an
#' indicator that SHOULD NOT be nowcast, and the rest of the pipeline runs
#' unchanged.
#'
#' The draw matrix has the name `<measure>_nowcasted`, as from
#' [nowcast_delay_ecdf_v1()], and holds the observed total. So every collapsed
#' quantile equals the observed total, also for the newest weeks.
#' @param x The `csfmt_reporting_triangle_v3` to pass through.
#' @param max_delay_days The delay horizon in days. The totals do not depend on
#'   it, because a later report counts in the last delay column.
#' @param denominator_col A denominator column to pass through in the same way.
#'   Its total also goes to `$data` as `<denominator_col>_observed`.
#' @returns A `csfmt_ensemble_v3` with one draw. `$data` holds `original`, the
#'   observed total.
#' @family nowcast engines
#' @seealso `vignette("pipeline", package = "csalert")`, stage 2, which scores it
#'   against [nowcast_delay_ecdf_v1()].
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday. The
#' # data stops at one as-of date, so the newest weeks are still incomplete.
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
#' # one draw, so every quantile equals the observed total, also for the
#' # newest weeks that are still incomplete
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
