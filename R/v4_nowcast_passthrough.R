# nowcast_passthrough_v4: a copy of nowcast_passthrough_to_ensemble_v1 on the
# v4 formats. It returns the counts reported so far as an ensemble with one
# draw, for an indicator that is not nowcast.

#' Build an ensemble from a reporting triangle with no nowcast
#'
#' Returns the counts reported so far as an ensemble with one draw. Use it for
#' an indicator that SHOULD NOT be nowcast.
#'
#' The method is that of [nowcast_passthrough_to_ensemble_v1()], and the draws
#' are identical. The draw matrix has the name of `value_col`, with no suffix.
#' It holds the observed total, which includes the reports at delay
#' `max_delay_days` or later. The function draws no random numbers.
#' @param x The `csfmt_reporting_triangle_v4` to pass through.
#' @param max_delay_days The delay horizon in days. The totals do not depend on
#'   it.
#' @param denominator_col A denominator column to pass through in the same way.
#'   Its total also goes to `$data` as `<denominator_col>_observed`.
#' @returns A `csfmt_ensemble_v4` with one draw per measure. `$data` holds
#'   `original`, the observed total.
#' @family v4 functions
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v4(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#' nowcast_passthrough_v4(tri, max_delay_days = 21)
#' @export
nowcast_passthrough_v4 <- function(x, max_delay_days, denominator_col = NULL) {
  stopifnot(inherits(x, "csfmt_reporting_triangle_v4"))
  val_col <- attr(x, "value_col")
  value_cols <- c(val_col, denominator_col)
  .v4_check_measure_names(value_cols)
  rts_num <- .v4_reporting_triangle_matrix(x, max_delay_days, val_col)
  series_ids <- names(rts_num)
  data <- .v4_triangle_frame(x, rts_num)

  draws <- list()
  for (vc in value_cols) {
    rts <- .v4_reporting_triangle_matrix(x, max_delay_days, vc)
    obs <- .v4_observed_total(rts, series_ids)
    draws[[vc]] <- matrix(obs, ncol = 1)
    if (!identical(vc, val_col)) {
      data[, (.v4_var(vc, role = "observed")) := obs]
    }
  }
  return(csfmt_ensemble_v4(
    data,
    id_cols = attr(x, "id_cols"),
    time_col = "isoyearweek",
    draws = draws
  ))
}
