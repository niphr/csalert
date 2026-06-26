# collapse: the single uncertainty -> summary reduction at the end of the
# draw-parallel pipeline. Each $draws measure matrix is reduced over the draw
# axis (rowQuantiles) into named quantile columns on $data; $draws is dropped.
# The result is the quantile-summary data.table (one row per series x time),
# ready to be healed into a csfmt_rts_data for plots/tables/seasonal methods.
#
# Lossy and one-way: all draw-level work (trend, mem/hlm classification) must
# happen BEFORE collapse, while the draws still exist.

#' Collapse a csfmt_ensemble to a quantile-summary data.table
#' @param ens A `csfmt_ensemble`.
#' @param probs Numeric vector of probabilities for the quantile columns.
#' @returns A `data.table`: `$data` plus `<measure>_qNNxN` columns for every
#'   measure in `$draws`; no draws.
#' @export
collapse <- function(ens, probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975)) {
  stopifnot(inherits(ens, "csfmt_ensemble"), is.numeric(probs))
  d <- data.table::copy(ens$data)

  for (m in names(ens$draws)) {
    q <- matrixStats::rowQuantiles(ens$draws[[m]], probs = probs, na.rm = TRUE)
    q <- matrix(q, nrow = nrow(d), ncol = length(probs))   # keep shape for 1-row/1-prob
    cols <- vapply(probs, function(p) csfmt_var(m, q = p), character(1))
    d[, (cols) := data.table::as.data.table(q)]
  }
  d[]
}
