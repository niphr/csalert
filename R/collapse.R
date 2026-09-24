# collapse: the single uncertainty -> summary reduction at the end of the
# draw-parallel pipeline. Each $draws measure matrix is reduced over the draw
# axis (rowQuantiles) into named quantile columns on $data; $draws is dropped.
# The result is the quantile-summary data.table (one row per series x time),
# ready to be healed into a csfmt_rts_data for plots/tables/seasonal methods.
#
# Lossy and one-way: all draw-level work (trend, mem/hlm classification) must
# happen BEFORE collapse, while the draws still exist.

#' Collapse the draws of an ensemble to quantiles
#'
#' Reduces every draw matrix to quantile columns, and drops the draws. It is the
#' last stage: no stage takes a collapsed table as input.
#'
#' A status matrix, one with a `levels` attribute, also gives a
#' `<measure>_prob_<level>` column per level, with the share of draws at that
#' level. Its quantile columns hold the code of the lowest level whose cumulative
#' share reaches the probability. Both ignore `NA` draws.
#' @param x The `csfmt_ensemble_v3` to collapse.
#' @param probs The probabilities of the quantile columns.
#' @param heal If `TRUE`, return a `csfmt_rts_data_v3` from
#'   `cstidy::set_csfmt_rts_data_v3()`, which adds the calendar columns.
#' @param ... Passed to the method.
#' @returns A copy of `$data` with a `<measure>_<q-label>` column for each
#'   measure and probability. It is a data.table, or a `csfmt_rts_data_v3` when
#'   `heal = TRUE`.
#' @family ensemble operations
#' @seealso `vignette("pipeline", package = "csalert")`, stage 8.
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' set.seed(1)
#' ens <- csfmt_ensemble_v3(
#'   d,
#'   id_cols = c("location_code", "age"),
#'   draws = list(numerator_nowcasted = matrix(rpois(3 * 100, 20), nrow = 3))
#' )
#'
#' # one column per probability, named by the naming grammar
#' r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
#' r[, .(
#'   isoyearweek,
#'   lo = numerator_nowcasted_q05x0,
#'   med = numerator_nowcasted_q50x0,
#'   hi = numerator_nowcasted_q95x0
#' )]
#'
#' # the quantile columns are all that the collapse adds, and the draws are gone
#' setdiff(names(r), names(ens$data))
#' @export
ens_collapse <- function(x, ...) UseMethod("ens_collapse")

#' @rdname ens_collapse
#' @export
ens_collapse.csfmt_ensemble_v3 <- function(
  x,
  probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
  heal = FALSE,
  ...
) {
  stopifnot(is.numeric(probs))
  ens <- x
  d <- data.table::copy(ens$data)

  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    levs <- attr(M, "levels")
    if (is.null(levs)) {
      # continuous: quantiles over the draw axis
      q <- matrixStats::rowQuantiles(M, probs = probs, na.rm = TRUE)
      q <- matrix(q, nrow = nrow(d), ncol = length(probs)) # keep shape for 1-row/1-prob
      cols <- vapply(probs, function(p) csfmt_var(m, q = p), character(1))
      d[, (cols) := data.table::as.data.table(q)]
    } else {
      # ordinal status: probability per level + ordinal quantiles
      collapse_status_into(d, m, M, levs, probs)
    }
  }

  if (heal) {
    if (!requireNamespace("cstidy", quietly = TRUE)) {
      stop("collapse(heal = TRUE) requires the 'cstidy' package", call. = FALSE)
    }
    cstidy::set_csfmt_rts_data_v3(d) # heal ONCE, here, into the clean csfmt
  }
  return(d[])
}

# Reduce an ordinal status code matrix (codes 1..K, with a "levels" attribute)
# into per-level probability columns and ordinal-quantile columns, by reference.
collapse_status_into <- function(d, measure, M, levs, probs) {
  K <- length(levs)
  n <- nrow(M)
  prob <- vapply(
    seq_len(K),
    function(k) rowMeans(M == k, na.rm = TRUE),
    numeric(n)
  )
  pcols <- vapply(levs, function(L) csfmt_var(measure, level = L), character(1))
  d[, (pcols) := data.table::as.data.table(prob)]

  # ordinal p-quantile = smallest level whose cumulative probability >= p
  cum <- matrixStats::rowCumsums(prob)
  qmat <- vapply(probs, function(p) pmin(rowSums(cum < p) + 1L, K), numeric(n))
  qmat <- matrix(qmat, nrow = n, ncol = length(probs))
  qcols <- vapply(probs, function(p) csfmt_var(measure, q = p), character(1))
  d[, (qcols) := data.table::as.data.table(qmat)]
  return(invisible(d))
}
