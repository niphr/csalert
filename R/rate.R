# add_rate: compute a rate measure (numerator / denominator) per draw.
#
# Rates (e.g. % positive) must be computed per draw to propagate uncertainty,
# then collapsed like any continuous measure. Because draws are index-aligned
# across measures (same column = same Monte-Carlo world), this is element-wise.
# denom = 0 -> NA (honest; do not fabricate a 0% that reads as a real drop).
# The numerator is a subset of the denominator, so the rate is capped at `per`
# (coherence guard); a violation warns rather than silently exceeding 100%.

#' Add a rate measure to an ensemble
#' @param ens A `csfmt_ensemble_v3`.
#' @param numerator,denominator Measure names present in `$draws`.
#' @param per Scaling factor (e.g. 100 for percent).
#' @param name Optional output measure name (defaults to the grammar name).
#' @returns `ens` with the rate measure added to `$draws`.
#' @export
add_rate <- function(ens, numerator, denominator, per = 100, name = NULL) {
  stopifnot(inherits(ens, "csfmt_ensemble_v3"))
  if (!all(c(numerator, denominator) %in% names(ens$draws)))
    stop("numerator and denominator must both be measures in $draws")

  N <- ens$draws[[numerator]]
  D <- ens$draws[[denominator]]
  if (any(N > D, na.rm = TRUE))
    warning("numerator > denominator in some draws; rate capped at `per`")

  rate <- per * N / D
  rate[!is.finite(rate)] <- NA_real_      # denom 0 (or NA) -> NA, not a fake 0
  rate[rate > per] <- per                 # coherence cap (num <= denom)

  if (is.null(name)) name <- csfmt_var(numerator, denom = denominator, per = per)
  ens$draws[[name]] <- rate
  validate_ensemble(ens)
}
