# nowcast_backtest / nowcast_score / nowcast_compare: a method-agnostic harness
# for validating and comparing nowcast engines by REPLAY.
#
# The reporting triangle already records, per cell, WHEN a count was reported --
# so we can reconstruct exactly what was known at any past week (`nowcast_censor`)
# without re-reading truncated raw data. Replaying an engine across a series of
# "as-of" weeks and scoring its nowcasts against the eventually-settled totals
# (`scoringutils`: WIS + interval coverage, by horizon) is how you tell whether a
# nowcast is any good -- and whether one engine beats another.
#
# The method contract is deliberately minimal: a nowcast method is a function
#   f(triangle) -> csfmt_ensemble_v3
# with all of ITS parameters baked in (e.g. via a closure). That keeps engines
# with different signatures (n_sim, priors, ...) composable through one interface:
#   nowcast_compare(tri, methods = list(
#     simple      = function(x) nowcast_simple_v1(x, max_delay = 5, n_sim = 1000),
#     passthrough = function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay = 5)))

#' Censor a reporting triangle to what was known "as of" a past week
#'
#' Keeps only cells reported on or before `as_of` and rebuilds the triangle, so
#' its as-of boundary and delay structure are exactly what an engine would have
#' seen at that week. The basis for replay-based backtesting.
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param as_of An ISO-week string; cells reported after it are dropped.
#' @returns A `csfmt_reporting_triangle_v3` censored to `as_of`.
#' @export
nowcast_censor <- function(triangle, as_of) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rep_col <- attr(triangle, "reporting_col")
  ref_col <- attr(triangle, "reference_col")
  val_col <- attr(triangle, "value_col")
  d <- data.table::as.data.table(triangle)
  d <- d[get(rep_col) <= as_of]
  if (!nrow(d)) stop("nothing reported on or before ", as_of)
  csfmt_reporting_triangle_v3(d, id_cols = attr(triangle, "id_cols"),
                              reference_col = ref_col, reporting_col = rep_col,
                              value_col = val_col)
}

#' The settled (eventually-observed) total per reference week
#'
#' Sums each reference week's counts across all delays up to `max_delay` -- the
#' quantity a nowcast is trying to predict -- and keeps only weeks old enough that
#' this total is settled (at least `max_delay` weeks before the triangle's as-of).
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param max_delay Delay horizon in weeks.
#' @returns A data.table `reference`, `truth`.
#' @export
nowcast_truth <- function(triangle, max_delay) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay)
  if (length(rts) != 1L)
    stop("nowcast_truth expects a single-series triangle; filter to one series first")
  refs  <- rts[[1]]$reference
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
#' @export
nowcast_backtest <- function(triangle, method, as_of_weeks = NULL, max_delay,
                             horizons = 1:2,
                             probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
                             measure = NULL, seed = NULL) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"), is.function(method))
  if (data.table::uniqueN(triangle$time_series_id) > 1L)
    stop("nowcast_backtest expects a single-series triangle; filter to one series first")
  if (is.null(measure))
    measure <- csfmt_var(attr(triangle, "value_col"), role = "nowcasted")
  weeks <- cstime::dates_by_isoyearweek$isoyearweek

  if (is.null(as_of_weeks)) {
    refs <- reporting_triangle_matrix(triangle, max_delay)[[1]]$reference
    as_of_weeks <- utils::tail(refs, max(0L, length(refs) - max_delay))
  }

  out <- list()
  for (as_of in as_of_weeks) {
    if (!is.null(seed)) set.seed(seed + match(as_of, weeks))   # reproducible per cell
    ens <- tryCatch(method(nowcast_censor(triangle, as_of)),
                    error = function(e) { warning("as_of ", as_of, ": ", conditionMessage(e),
                                                  call. = FALSE); NULL })
    if (is.null(ens)) next
    q <- ens_collapse(ens, probs = probs)
    q[, .horizon := match(as_of, weeks) - match(get("isoyearweek"), weeks)]
    q <- q[.horizon %in% horizons]
    if (!nrow(q)) next
    for (p in probs) {
      col <- csfmt_var(measure, q = p)
      if (!col %in% names(q)) next
      out[[length(out) + 1L]] <- data.table::data.table(
        reference = q$isoyearweek, as_of = as_of, horizon = q$.horizon,
        quantile_level = p, predicted = q[[col]])
    }
  }
  data.table::rbindlist(out)
}

#' Score a backtest against settled truth (WIS + interval coverage, by horizon)
#'
#' Wraps `scoringutils`: joins the replayed quantile nowcasts to the settled
#' totals and returns the weighted interval score and empirical interval coverage,
#' summarised `by` (default horizon).
#' @param backtest Output of [nowcast_backtest].
#' @param truth Output of [nowcast_truth].
#' @param by Grouping columns for the summary (default "horizon").
#' @returns `list(scores, coverage)` (both data.tables).
#' @export
nowcast_score <- function(backtest, truth, by = "horizon") {
  if (!requireNamespace("scoringutils", quietly = TRUE))
    stop("nowcast_score requires the 'scoringutils' package")
  if (!nrow(backtest)) stop("empty backtest: no nowcasts to score")
  d <- merge(data.table::as.data.table(backtest),
             data.table::as.data.table(truth), by = "reference")
  if (!nrow(d)) stop("no overlap between backtest reference weeks and settled truth")
  fc <- scoringutils::as_forecast_quantile(d,
          forecast_unit = c("reference", "horizon"),
          observed = "truth", predicted = "predicted", quantile_level = "quantile_level")
  list(scores   = data.table::as.data.table(
                    scoringutils::summarise_scores(scoringutils::score(fc), by = by)),
       coverage = data.table::as.data.table(scoringutils::get_coverage(fc, by = by)))
}

#' Compare several nowcast methods on one triangle (a scorecard)
#'
#' Backtests and scores each method on the same replay, and stacks the per-horizon
#' scores with a `method` column so engines can be ranked head-to-head (e.g. a
#' real nowcast vs the passthrough baseline, or two nowcast engines).
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param methods Named list of methods `f(triangle) -> csfmt_ensemble_v3`.
#' @param as_of_weeks,max_delay,horizons,probs Passed to [nowcast_backtest].
#' @param by Grouping for the score summary (default "horizon").
#' @returns A data.table of per-horizon scores with a `method` column.
#' @export
nowcast_compare <- function(triangle, methods, max_delay, as_of_weeks = NULL,
                            horizons = 1:2,
                            probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
                            by = "horizon") {
  stopifnot(is.list(methods), length(methods) > 0, !is.null(names(methods)))
  truth <- nowcast_truth(triangle, max_delay)
  out <- list()
  for (nm in names(methods)) {
    bt <- nowcast_backtest(triangle, methods[[nm]], as_of_weeks = as_of_weeks,
                           max_delay = max_delay, horizons = horizons, probs = probs)
    if (!nrow(bt)) { warning("method '", nm, "' produced no nowcasts", call. = FALSE); next }
    sc <- nowcast_score(bt, truth, by = by)
    s <- sc$scores; s[, method := nm]
    out[[nm]] <- s
  }
  data.table::rbindlist(out, fill = TRUE)
}

#' Validate one nowcast method on one triangle (backtest -> score, in one call)
#'
#' Thin wrapper: replay `method` across `as_of_weeks`, then score against settled
#' truth. Seeded per cell (`seed`) so the scorecard is a deterministic function of
#' the data -- recompute it every run and overwrite; the numbers don't drift with
#' run cadence. Returns NULL if the replay produced nothing (e.g. a passthrough on
#' a delay-0 series, or too little history).
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param method A function `f(triangle) -> csfmt_ensemble_v3` (params baked in).
#' @param max_delay Delay horizon in weeks.
#' @param as_of_weeks,horizons,probs,seed Passed to [nowcast_backtest].
#' @param by Grouping for the score summary (default "horizon").
#' @returns `list(scores, coverage)` (as from [nowcast_score]) or NULL.
#' @export
nowcast_validate <- function(triangle, method, max_delay, as_of_weeks = NULL,
                             horizons = 1:2,
                             probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
                             by = "horizon", seed = NULL) {
  bt <- nowcast_backtest(triangle, method, as_of_weeks = as_of_weeks,
                         max_delay = max_delay, horizons = horizons,
                         probs = probs, seed = seed)
  if (!nrow(bt)) return(NULL)
  nowcast_score(bt, nowcast_truth(triangle, max_delay), by = by)
}
