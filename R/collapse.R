# collapse: the single uncertainty -> summary reduction at the end of the
# draw-parallel pipeline. Each $draws measure matrix is reduced over the draw
# axis (rowQuantiles) into named quantile columns on $data; $draws is dropped.
# The result is the quantile-summary data.table (one row per series x time),
# ready to be healed into a csfmt_rts_data for plots/tables/seasonal methods.
#
# Lossy and one-way: all draw-level work (trend, mem/hlm classification) must
# happen BEFORE collapse, while the draws still exist.

#' Collapse a csfmt_ensemble_v3 to a quantile-summary
#' @param ens A `csfmt_ensemble_v3`.
#' @param probs Numeric vector of probabilities for the quantile columns.
#' @param heal If TRUE, heal the result into a `cstidy::csfmt_rts_data_v3` (the
#'   clean weekly csfmt) instead of returning a plain data.table.
#' @returns A `data.table` (or `csfmt_rts_data_v3` if `heal=TRUE`): `$data` plus
#'   `<measure>_qNNxN` columns for every measure in `$draws`; no draws.
#' @export
collapse <- function(ens, probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
                     heal = FALSE) {
  stopifnot(inherits(ens, "csfmt_ensemble_v3"), is.numeric(probs))
  d <- data.table::copy(ens$data)

  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    levs <- attr(M, "levels")
    if (is.null(levs)) {
      # continuous: quantiles over the draw axis
      q <- matrixStats::rowQuantiles(M, probs = probs, na.rm = TRUE)
      q <- matrix(q, nrow = nrow(d), ncol = length(probs))  # keep shape for 1-row/1-prob
      cols <- vapply(probs, function(p) csfmt_var(m, q = p), character(1))
      d[, (cols) := data.table::as.data.table(q)]
    } else {
      # ordinal status: probability per level + ordinal quantiles
      collapse_status_into(d, m, M, levs, probs)
    }
  }

  if (heal) {
    if (!requireNamespace("cstidy", quietly = TRUE))
      stop("collapse(heal = TRUE) requires the 'cstidy' package")
    cstidy::set_csfmt_rts_data_v3(d)   # heal ONCE, here, into the clean csfmt
  }
  d[]
}

# Reduce an ordinal status code matrix (codes 1..K, with a "levels" attribute)
# into per-level probability columns and ordinal-quantile columns, by reference.
collapse_status_into <- function(d, measure, M, levs, probs) {
  K <- length(levs)
  n <- nrow(M)
  prob <- vapply(seq_len(K), function(k) rowMeans(M == k, na.rm = TRUE), numeric(n))
  pcols <- vapply(levs, function(L) csfmt_var(measure, level = L), character(1))
  d[, (pcols) := data.table::as.data.table(prob)]

  # ordinal p-quantile = smallest level whose cumulative probability >= p
  cum <- matrixStats::rowCumsums(prob)
  qmat <- vapply(probs, function(p) pmin(rowSums(cum < p) + 1L, K), numeric(n))
  qmat <- matrix(qmat, nrow = n, ncol = length(probs))
  qcols <- vapply(probs, function(p) csfmt_var(measure, q = p), character(1))
  d[, (qcols) := data.table::as.data.table(qmat)]
  invisible(d)
}
