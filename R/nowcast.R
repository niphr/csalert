# nowcast (passthrough): csfmt_reporting_triangle_v3 -> csfmt_ensemble_v3.
#
# The passthrough engine collapses the triangle to the observed (reported-so-far)
# totals per reference week and wraps them as a degenerate single-draw ensemble --
# for indicators that should NOT be nowcast-completed. The modelling nowcast
# engines live in their own files (see nowcast_quasipoisson_v1).

#' Build an ensemble from a reporting triangle WITHOUT nowcasting (passthrough)
#'
#' Collapse the triangle to the observed (reported-so-far) totals per reference
#' week and wrap them as a degenerate single-draw ensemble. An indicator that
#' should NOT be nowcast-completed (because reporting is effectively complete, or
#' the analyst has chosen not to model the delay) then flows through the SAME
#' rate/trend/MEM/collapse pipeline with its observed values unchanged. It emits
#' the same `<measure>_nowcasted` columns as the modelling engines -- here equal to
#' the observed value -- so all downstream code is identical; the single draw makes
#' every collapsed quantile equal the observed point.
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param max_delay Delay horizon (defines the contiguous reference grid).
#' @param denominator_col Optional denominator column, carried through the same
#'   way (its observed total is also surfaced as `<denom>_observed`).
#' @returns A `csfmt_ensemble_v3` with single-column draw matrices.
#' @export
nowcast_passthrough_to_ensemble_v1 <- function(x, max_delay, denominator_col = NULL) {
  stopifnot(inherits(x, "csfmt_reporting_triangle_v3"))
  id_cols <- attr(x, "id_cols")
  val_col <- attr(x, "value_col")
  value_cols <- c(val_col, denominator_col)
  d_tri <- data.table::as.data.table(x)

  rts_num <- reporting_triangle_matrix(x, max_delay, value_col = val_col)
  series_ids <- names(rts_num)

  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(1L, length(refs))]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay, value_col = vc)
    obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
    draws[[csfmt_var(vc, role = "nowcasted")]] <- matrix(obs, ncol = 1)
    if (!identical(vc, val_col)) data[, (csfmt_var(vc, role = "observed")) := obs]
  }

  csfmt_ensemble_v3(data, id_cols = id_cols, time_col = "isoyearweek", draws = draws)
}
