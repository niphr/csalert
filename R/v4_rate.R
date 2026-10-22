# ens_add_rate_v4: a copy of ens_add_rate.csfmt_ensemble_v3 on the v4 format.
# It divides one draw matrix by another, draw by draw.

#' Add a rate to a csfmt_ensemble_v4
#'
#' Divides one draw matrix by another, draw by draw, and adds the result as a
#' new draw matrix. Column `j` is the same draw in every measure, so the rate
#' carries the uncertainty of both.
#'
#' The method is that of [ens_add_rate()] for a `csfmt_ensemble_v3`, and the
#' rate is identical. The rate is `per * numerator / denominator`. A zero or
#' `NA` denominator gives `NA`, also for `0 / 0`. The numerator is a subset of
#' the denominator, so the rate is capped at `per`. A draw with a numerator
#' above its denominator gives a warning.
#'
#' On a compressed ensemble from [as_ensemble_v4()], the function rebuilds the
#' numerator and the denominator. Their draws are independent, as in a full
#' ensemble from [nowcast_ecdf_v4()]. It then writes the median and the 9
#' percentiles of the rate to `$data`, as [ens_compress_v4()] does.
#' @param x The `csfmt_ensemble_v4`, full or compressed, that holds both
#'   measures.
#' @param numerator,denominator The names of two draw matrices in `$draws`.
#' @param per The scale of the rate. `100` gives a percentage.
#' @param name The name of the new draw matrix. It MUST be at most 63 bytes,
#'   and it MUST NOT end in a reserved suffix such as `_trend_gr` or `_hlm`.
#'   It MUST NOT be the name of a column of `$data`, such as an identity
#'   column or the time column. In a compressed ensemble, it MAY be the name
#'   of a stored measure, whose columns the rate then replaces.
#' @returns `x` with the rate in `$draws[[name]]`. A draw matrix with that name
#'   is replaced.
#' @family v4 functions
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' # The numerator is a subset of the denominator: positive tests out of tests.
#' set.seed(1)
#' tested <- matrix(rpois(3 * 100, 200), nrow = 3)
#' positive <- matrix(rbinom(length(tested), tested, 0.1), nrow = 3)
#' ens <- csfmt_ensemble_v4(
#'   d,
#'   id_cols = "location_code",
#'   draws = list(positive = positive, tested = tested)
#' )
#' ens <- ens_add_rate_v4(
#'   ens,
#'   numerator = "positive",
#'   denominator = "tested",
#'   per = 100,
#'   name = "positive_vs_tested_pr100"
#' )
#' names(ens$draws)
#' @export
ens_add_rate_v4 <- function(x, numerator, denominator, per = 100, name) {
  .v4_validate_ensemble(x)
  .v4_check_measure_names(name)
  compressed <- identical(x$state, "compressed")
  stored <- compressed && name %in% .v4_stored_measures(names(x$data))
  if (name %in% names(x$data) && !stored) {
    stop(
      "`name` '",
      name,
      "' is a column of $data. A draw matrix MUST have another name.",
      call. = FALSE
    )
  }
  if (!all(c(numerator, denominator) %in% .v4_measures(x))) {
    stop(
      "numerator and denominator must both be measures in $draws",
      call. = FALSE
    )
  }

  if (compressed) {
    .v4_check_names(unique(c(names(x$data), .v4_summary_names(name))))
  }

  N <- .v4_draws(x, numerator)
  D <- .v4_draws(x, denominator)
  if (any(N > D, na.rm = TRUE)) {
    warning(
      "numerator > denominator in some draws; rate capped at `per`",
      call. = FALSE
    )
  }

  rate <- per * N / D
  # A zero or NA denominator gives NA, not a rate of 0.
  rate[!is.finite(rate)] <- NA_real_
  # The numerator is a subset of the denominator.
  rate[rate > per] <- per

  # `x` is valid, and `name` passed .v4_check_measure_names() and is no
  # column of $data, so the new ensemble is valid. A draw matrix with that
  # name is replaced. A compressed ensemble also gets the summary columns of
  # the rate, which replace those of a stored measure with that name.
  x$draws[[name]] <- rate
  if (compressed) {
    d <- data.table::copy(x$data)
    .v4_summary_into(d, name, rate)
    x$data <- d
    .v4_validate_ensemble(x)
  }
  return(x)
}
