# nowcast_censor / nowcast_truth / nowcast_backtest: the REPLAY mechanics behind
# the nowcast diagnostics.
#
# The reporting triangle already records, per cell, WHEN a count was reported --
# so we can reconstruct exactly what was known at any past week (`nowcast_censor`)
# without re-reading truncated raw data. Replaying an engine across a series of
# "as-of" weeks (`nowcast_backtest`) and comparing to the eventually-settled totals
# (`nowcast_truth`) is how you tell whether a nowcast is any good. The scoring on
# top of a replay lives in nowcast_evaluate.R (`nowcast_evaluate_v1`).
#
# The method contract is deliberately minimal: a nowcast method is a function
#   f(triangle) -> csfmt_ensemble_v3
# with all of ITS parameters baked in (e.g. via a closure). That keeps engines
# with different signatures (n_sim, priors, ...) composable through one interface.

#' Censor a reporting triangle to what was known "as of" a past week
#'
#' Keeps only cells reported on or before `as_of` and rebuilds the triangle, so
#' its as-of boundary and delay structure are exactly what an engine would have
#' seen at that week. The basis for replay-based backtesting.
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param as_of An ISO-week string; cells reported after it are dropped.
#' @returns A `csfmt_reporting_triangle_v3` censored to `as_of`.
#' @family nowcast diagnostics
#' @seealso Neither package vignette covers this function.
#'   \code{vignette("nowcasting", package = "csalert")} describes replay in prose
#'   and then calls \code{\link{nowcast_evaluate_v1}}, which censors for you.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' i <- match("2023-01", w)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[isoyearweek_reporting <= w[i + 39]]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' # rewind to what was known nine weeks earlier
#' past <- nowcast_censor(tri, as_of = w[i + 30])
#' c(now = attr(tri, "as_of"), then = attr(past, "as_of"))
#' c(rows_now = nrow(tri), rows_then = nrow(past))
#' @export
nowcast_censor <- function(triangle, as_of) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rep_col <- attr(triangle, "reporting_col")
  ref_col <- attr(triangle, "reference_col")
  val_col <- attr(triangle, "value_col")
  d <- data.table::as.data.table(triangle)
  d <- d[get(rep_col) <= as_of]
  if (!nrow(d)) {
    stop("nothing reported on or before ", as_of)
  }
  csfmt_reporting_triangle_v3(
    d,
    id_cols = attr(triangle, "id_cols"),
    reference_col = ref_col,
    reporting_col = rep_col,
    value_col = val_col
  )
}

#' The settled (eventually-observed) total per reference week
#'
#' Sums each reference week's counts across all delays up to `max_delay` -- the
#' quantity a nowcast is trying to predict -- and keeps only weeks old enough that
#' this total is settled (at least `max_delay` weeks before the triangle's as-of).
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param max_delay Delay horizon in weeks.
#' @returns A data.table `reference`, `truth`.
#' @family nowcast diagnostics
#' @seealso Neither package vignette covers this function.
#'   \code{vignette("nowcasting", package = "csalert")} scores a nowcast against
#'   settled truth through \code{\link{nowcast_evaluate_v1}}, which calls this
#'   function for you.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' i <- match("2023-01", w)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[isoyearweek_reporting <= w[i + 39]]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' truth <- nowcast_truth(tri, max_delay = 3)
#'
#' # the two newest weeks are missing: they are not settled yet, so they have no
#' # truth to be scored against
#' tail(truth, 3)
#' c(reference_weeks = 40L, settled = nrow(truth))
#' @export
nowcast_truth <- function(triangle, max_delay) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay)
  if (length(rts) != 1L) {
    stop(
      "nowcast_truth expects a single-series triangle; filter to one series first"
    )
  }
  refs <- rts[[1]]$reference
  total <- rowSums(rts[[1]]$mat)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  age_w <- match(attr(triangle, "as_of"), weeks) - match(refs, weeks)
  settled <- age_w >= (max_delay - 1L)
  data.table::data.table(reference = refs, truth = total)[settled]
}

#' Replay a nowcast method across as-of weeks (backtest)
#'
#' For each `as_of` week, censor the triangle to what was known then, run the
#' method, collapse to quantiles, and collect the nowcast for the reference weeks
#' at the requested horizons (horizon = weeks between reference and as-of). An
#' as-of week whose method call errors (e.g. too little history) is skipped with a
#' warning rather than aborting the sweep.
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param method A function `f(triangle) -> csfmt_ensemble_v3` (params baked in).
#' @param as_of_weeks ISO-week strings to replay. Default: every reference week
#'   after a `max_delay`-week burn-in, replayed as-of itself.
#' @param max_delay Delay horizon (used for the default as-of set and burn-in).
#' @param horizons Integer weeks-back to keep (0 = the as-of week itself).
#' @param probs Quantile probabilities to extract.
#' @param measure Ensemble measure to score; default the numerator's nowcast.
#' @param seed Optional integer base seed. Each as-of is seeded as
#'   `seed + week-index`, so a given cell is reproducible regardless of the as-of
#'   list order (the nowcast draws for week W depend only on `seed` and `W`).
#' @returns A long data.table: `reference`, `as_of`, `horizon`, `quantile_level`,
#'   `predicted`.
#' @family nowcast diagnostics
#' @seealso Neither package vignette covers this function.
#'   \code{vignette("nowcasting", package = "csalert")} reaches the same replay
#'   through \code{\link{nowcast_evaluate_v1}}, which wraps it and scores the
#'   result. Use this function directly when you want the raw replayed quantiles.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek
#' i <- match("2023-01", w)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[isoyearweek_reporting <= w[i + 39]]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' # a method is f(triangle) -> ensemble, with its own parameters baked in
#' method <- function(x) nowcast_quasipoisson_v1(x, max_delay = 3, n_sim = 200)
#'
#' # Replay 19 as-of weeks. This window is a runtime choice, not a fitting
#' # boundary: the engine needs only three settled training rows, and with fewer
#' # it returns the observed totals rather than failing. Leaving `as_of_weeks`
#' # NULL replays every week after the burn-in, which is slower.
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay = 3,
#'   as_of_weeks = w[i + 20:38],
#'   horizons = 0:1,
#'   probs = c(0.05, 0.5, 0.95),
#'   seed = 1
#' )
#' head(bt, 6)
#' @export
nowcast_backtest <- function(
  triangle,
  method,
  as_of_weeks = NULL,
  max_delay,
  horizons = 1:2,
  probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
  measure = NULL,
  seed = NULL
) {
  stopifnot(
    inherits(triangle, "csfmt_reporting_triangle_v3"),
    is.function(method)
  )
  if (data.table::uniqueN(triangle$time_series_id) > 1L) {
    stop(
      "nowcast_backtest expects a single-series triangle; filter to one series first"
    )
  }
  if (is.null(measure)) {
    measure <- csfmt_var(attr(triangle, "value_col"), role = "nowcasted")
  }
  weeks <- cstime::dates_by_isoyearweek$isoyearweek

  if (is.null(as_of_weeks)) {
    refs <- reporting_triangle_matrix(triangle, max_delay)[[1]]$reference
    as_of_weeks <- utils::tail(refs, max(0L, length(refs) - max_delay))
  }

  out <- list()
  for (as_of in as_of_weeks) {
    if (!is.null(seed)) {
      set.seed(seed + match(as_of, weeks))
    } # reproducible per cell
    ens <- tryCatch(
      method(nowcast_censor(triangle, as_of)),
      error = function(e) {
        warning("as_of ", as_of, ": ", conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (is.null(ens)) {
      next
    }
    q <- ens_collapse(ens, probs = probs)
    q[, .horizon := match(as_of, weeks) - match(get("isoyearweek"), weeks)]
    q <- q[.horizon %in% horizons]
    if (!nrow(q)) {
      next
    }
    for (p in probs) {
      col <- csfmt_var(measure, q = p)
      if (!col %in% names(q)) {
        next
      }
      out[[length(out) + 1L]] <- data.table::data.table(
        reference = q$isoyearweek,
        as_of = as_of,
        horizon = q$.horizon,
        quantile_level = p,
        predicted = q[[col]]
      )
    }
  }
  data.table::rbindlist(out)
}
