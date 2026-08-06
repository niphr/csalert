# add_rate: compute a rate measure (numerator / denominator) per draw.
#
# Rates (e.g. % positive) must be computed per draw to propagate uncertainty,
# then collapsed like any continuous measure. Because draws are index-aligned
# across measures (same column = same Monte-Carlo world), this is element-wise.
# denom = 0 -> NA (honest; do not fabricate a 0% that reads as a real drop).
# The numerator is a subset of the denominator, so the rate is capped at `per`
# (coherence guard); a violation warns rather than silently exceeding 100%.

#' Add a rate measure to an ensemble
#'
#' An ensemble operation (`ens_` family). It dispatches on the ensemble class, so
#' the class -- not a name prefix on the caller -- carries the "operates on an
#' ensemble" meaning. That matches [nowcast_quasipoisson_v1()] and
#' [short_term_trend()].
#' @param x A `csfmt_ensemble_v3`.
#' @param numerator,denominator Measure names present in `$draws`.
#' @param per Scaling factor (e.g. 100 for percent).
#' @param name Optional output measure name (defaults to the grammar name).
#' @param ... Passed to methods.
#' @returns `x` with the rate measure added to `$draws`.
#' @family ensemble operations
#' @seealso \code{vignette("pipeline", package = "csalert")}, which runs this
#'   function as stage 4 of its pipeline, on a numerator and denominator that
#'   were nowcast together.
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' # The numerator must be a SUBSET of the denominator (tests positive out of
#' # tests taken), so simulate the denominator first and the numerator
#' # conditionally on it. Two independent Poissons would not be a proportion.
#' set.seed(1)
#' denom <- matrix(rpois(3 * 100, 200), nrow = 3)
#' numer <- matrix(rbinom(length(denom), size = denom, prob = 0.10), nrow = 3)
#' ens <- csfmt_ensemble_v3(
#'   d,
#'   id_cols = c("location_code", "age"),
#'   draws = list(
#'     numerator_nowcasted = numer,
#'     denominator_nowcasted = denom
#'   )
#' )
#'
#' ens <- ens_add_rate(
#'   ens,
#'   numerator = "numerator_nowcasted",
#'   denominator = "denominator_nowcasted",
#'   per = 100
#' )
#'
#' # the rate is a third draw matrix, named by the grammar
#' names(ens$draws)
#'
#' # its interval carries the uncertainty of both measures
#' r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
#' r[, .(
#'   isoyearweek,
#'   lo = numerator_nowcasted_vs_denominator_nowcasted_pr100_q05x0,
#'   med = numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0,
#'   hi = numerator_nowcasted_vs_denominator_nowcasted_pr100_q95x0
#' )]
#' @export
ens_add_rate <- function(x, ...) UseMethod("ens_add_rate")

#' @rdname ens_add_rate
#' @export
ens_add_rate.csfmt_ensemble_v3 <- function(
  x,
  numerator,
  denominator,
  per = 100,
  name = NULL,
  ...
) {
  if (!all(c(numerator, denominator) %in% names(x$draws))) {
    stop("numerator and denominator must both be measures in $draws")
  }

  N <- x$draws[[numerator]]
  D <- x$draws[[denominator]]
  if (any(N > D, na.rm = TRUE)) {
    warning("numerator > denominator in some draws; rate capped at `per`")
  }

  rate <- per * N / D
  rate[!is.finite(rate)] <- NA_real_ # denom 0 (or NA) -> NA, not a fake 0
  rate[rate > per] <- per # coherence cap (num <= denom)

  if (is.null(name)) {
    name <- csfmt_var(numerator, denom = denominator, per = per)
  }
  x$draws[[name]] <- rate
  validate_ensemble(x)
}
