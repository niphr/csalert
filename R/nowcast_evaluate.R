# nowcast_evaluate_v1: replay nowcast method(s) over a triangle and score each on
# interval coverage + point-estimate revision, in ONE per-horizon table. Pass one
# method or a named list; a shared seed pairs them (common random numbers). Feed
# the result to nowcast_recommend_v1 to pick a winner.
#
# For each forecast (a reference week at a given horizon), joined to its settled
# truth, we read off two scale-free things:
#   - COVERAGE: is the truth inside the 50% / 90% central interval? (interval
#     honesty; target 0.50 / 0.90) -- computed directly from the interval
#     quantiles, so no scoringutils.
#   - REVISION: how far the published median sits from the settled truth, as a
#     fraction of the truth -- signed (bias), absolute (typical move), a 5-95%
#     band, and the tail exceedance probabilities.

# The per-backtest scorer: join one method's replayed quantile nowcasts to the
# settled truth and summarise coverage + revision by group. Internal -- callers go
# through nowcast_evaluate_v1 (which does the replay).
.evaluate_backtest <- function(backtest, truth, by = "horizon", thresholds = c(0.25, 0.5)) {
  bt <- data.table::as.data.table(backtest)
  if (!nrow(bt)) stop("empty backtest: nothing to evaluate")
  d <- merge(bt, data.table::as.data.table(truth), by = "reference")
  d <- d[is.finite(truth)]
  if (!nrow(d)) stop("no overlap between backtest reference weeks and settled truth")

  # one row per forecast unit (reference x horizon x ...) with the quantiles needed
  unit <- intersect(c("reference", "as_of", "horizon"), names(d))
  qcol <- function(p, nm) {
    x <- d[quantile_level == p, c(unit, "predicted"), with = FALSE]
    data.table::setnames(x, "predicted", nm)[]
  }
  truth_u <- unique(d[, c(unit, "truth"), with = FALSE])
  m <- Reduce(function(a, b) merge(a, b, by = unit),
              list(truth_u, qcol(0.05, "lo90"), qcol(0.95, "hi90"),
                   qcol(0.25, "lo50"), qcol(0.75, "hi50"), qcol(0.5, "med")))
  if (!nrow(m))
    stop("backtest is missing the 0.05/0.25/0.5/0.75/0.95 quantiles needed to evaluate")

  m[, `:=`(in90 = truth >= lo90 & truth <= hi90,
           in50 = truth >= lo50 & truth <= hi50)]
  m[truth > 0, rel := (med - truth) / truth]        # relative revision (undefined at truth 0)

  m[, {
    r <- rel[is.finite(rel)]; a <- abs(r); has <- length(r) > 0
    c(list(n             = .N,
           coverage_50   = round(mean(in50), 3),
           coverage_90   = round(mean(in90), 3),
           median_signed = if (has) round(stats::median(r), 4) else NA_real_,
           median_abs    = if (has) round(stats::median(a), 4) else NA_real_,
           q05           = if (has) round(stats::quantile(r, 0.05, names = FALSE), 4) else NA_real_,
           q95           = if (has) round(stats::quantile(r, 0.95, names = FALSE), 4) else NA_real_),
      stats::setNames(lapply(thresholds,
                             function(t) if (has) round(mean(a > t), 4) else NA_real_),
                      paste0("p_gt_", thresholds * 100)))
  }, by = by]
}

#' Evaluate nowcast method(s): interval coverage + point-estimate revision
#'
#' Replays each method over the triangle (backtest) and scores it on interval
#' coverage (are the intervals honest?) + point-estimate revision (how much will
#' the number still move?), stacked into one per-horizon table with a `method`
#' column. Pass a single method or a named list; a shared `seed` pairs them (common
#' random numbers) so a head-to-head is apples-to-apples. Coverage is read straight
#' off the interval quantiles, so this needs no `scoringutils`. Feed the result to
#' [nowcast_recommend_v1] to pick a winner.
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param methods A method `f(triangle) -> csfmt_ensemble_v3`, or a NAMED list of
#'   them (each with its parameters baked in, e.g. via a closure).
#' @param max_delay Delay horizon in weeks.
#' @param as_of_weeks,horizons,probs,seed Passed to [nowcast_backtest]. `seed` is
#'   shared across methods, so the comparison is paired.
#' @param by Grouping for the evaluation summary (default "horizon").
#' @param thresholds Absolute-revision cut-offs to report the exceedance
#'   probability for (default 25\% and 50\%).
#' @returns A data.table, one row per group x method: `n`, interval coverage
#'   (`coverage_50`, `coverage_90`), the point-estimate revision (`median_signed`
#'   bias, `median_abs`, `q05`/`q95` band, `p_gt_<t>` tails) and `method`.
#' @examples
#' # a small reporting triangle: 30 weeks, each reported over delays 0-2
#' w <- cstime::dates_by_isoyearweek$isoyearweek; i <- match("2023-01", w)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:29, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:29, each = 3) + rep(0:2, 30)],
#'   numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
#' tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
#'
#' # one method:
#' nowcast_evaluate_v1(tri, function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay = 3),
#'                     max_delay = 3, horizons = 0:2, seed = 1)
#' # several, paired, then pick a winner:
#' ev <- nowcast_evaluate_v1(tri, max_delay = 3, horizons = 0:2, seed = 1, methods = list(
#'   passthrough = function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay = 3)))
#' nowcast_recommend_v1(ev, configured = "passthrough")$recommended
#' @export
nowcast_evaluate_v1 <- function(triangle, methods, max_delay, as_of_weeks = NULL,
                                horizons = 1:2,
                                probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
                                by = "horizon", thresholds = c(0.25, 0.5), seed = NULL) {
  if (is.function(methods)) methods <- list(method = methods)       # single -> one-element menu
  stopifnot(is.list(methods), length(methods) > 0, !is.null(names(methods)))
  truth <- nowcast_truth(triangle, max_delay)
  out <- list()
  for (nm in names(methods)) {
    bt <- nowcast_backtest(triangle, methods[[nm]], as_of_weeks = as_of_weeks,
                           max_delay = max_delay, horizons = horizons, probs = probs, seed = seed)
    if (!nrow(bt)) { warning("method '", nm, "' produced no nowcasts", call. = FALSE); next }
    ev <- .evaluate_backtest(bt, truth, by = by, thresholds = thresholds)
    ev[, method := nm]
    out[[nm]] <- ev
  }
  data.table::rbindlist(out, fill = TRUE)
}

#' Recommend a nowcast model from a head-to-head evaluation
#'
#' Ranks the methods in a [nowcast_evaluate_v1] table by their mean score across
#' horizons (default the absolute revision -- the point estimate that settles
#' fastest) and audits a configured choice: it "meets" the recommendation when its
#' mean score is within `margin` of the best. Lets a pipeline keep a fixed
#' configured model while flagging when a candidate clearly beats it.
#' @param evaluation A [nowcast_evaluate_v1] output (per-horizon evaluations with a
#'   `method` column).
#' @param configured The method label currently in production.
#' @param metric Column to rank on, smaller = better. Default `"median_abs"`.
#' @param margin Relative tolerance: `configured` meets the recommendation when
#'   its mean metric <= best * (1 + margin). Default 0.05.
#' @returns A list: `configured`, `configured_score`, `recommended`,
#'   `recommended_score`, `meets` (logical), and `by_method` (a data.table of the
#'   per-method mean metric, ascending).
#' @examples
#' cmp <- data.table::data.table(
#'   horizon    = rep(0:1, 2),
#'   median_abs = c(0.30, 0.05, 0.10, 0.02),      # "fast" revises less than "slow"
#'   method     = rep(c("slow", "fast"), each = 2))
#' nowcast_recommend_v1(cmp, configured = "slow")$recommended   # "fast"
#' @export
nowcast_recommend_v1 <- function(evaluation, configured, metric = "median_abs",
                                 margin = 0.05) {
  d <- data.table::as.data.table(evaluation)
  stopifnot("method" %in% names(d), metric %in% names(d))
  by_method <- d[, .(score = mean(as.numeric(get(metric)), na.rm = TRUE)), by = "method"]
  data.table::setorder(by_method, score)
  recommended <- by_method$method[1]; best <- by_method$score[1]
  conf <- by_method[method == configured]$score
  conf <- if (length(conf)) conf[1] else NA_real_
  list(configured        = configured,
       configured_score  = round(conf, 4),
       recommended       = recommended,
       recommended_score = round(best, 4),
       meets             = isTRUE(conf <= best * (1 + margin)),
       by_method         = by_method)
}
