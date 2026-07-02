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
#' An ensemble operation (`ens_` family): dispatches on the ensemble class, so
#' the class -- not a name prefix on the caller -- carries the "operates on an
#' ensemble" meaning, matching [nowcast_quasipoisson_v1()] / [short_term_trend()].
#' @param x A `csfmt_ensemble_v3`.
#' @param numerator,denominator Measure names present in `$draws`.
#' @param per Scaling factor (e.g. 100 for percent).
#' @param name Optional output measure name (defaults to the grammar name).
#' @param ... Passed to methods.
#' @returns `x` with the rate measure added to `$draws`.
#' @export
ens_add_rate <- function(x, ...) UseMethod("ens_add_rate")

#' @rdname ens_add_rate
#' @export
ens_add_rate.csfmt_ensemble_v3 <- function(x, numerator, denominator, per = 100,
                                            name = NULL, ...) {
  if (!all(c(numerator, denominator) %in% names(x$draws)))
    stop("numerator and denominator must both be measures in $draws")

  N <- x$draws[[numerator]]
  D <- x$draws[[denominator]]
  if (any(N > D, na.rm = TRUE))
    warning("numerator > denominator in some draws; rate capped at `per`")

  rate <- per * N / D
  rate[!is.finite(rate)] <- NA_real_      # denom 0 (or NA) -> NA, not a fake 0
  rate[rate > per] <- per                 # coherence cap (num <= denom)

  if (is.null(name)) name <- csfmt_var(numerator, denom = denominator, per = per)
  x$draws[[name]] <- rate
  validate_ensemble(x)
}
