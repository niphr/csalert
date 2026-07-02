# nowcast_evaluate_v1: the point + interval evaluation of a nowcast backtest, in
# ONE per-horizon table -- what used to be two calls (coverage via scoringutils,
# revision off the medians). Coverage is just "is the truth inside the interval?",
# so it is computed directly from the interval quantiles -- no scoringutils.
#
# Joining each forecast (a reference week at a given horizon) to its settled truth,
# we read off two scale-free things:
#   - COVERAGE: is the truth inside the 50% / 90% central interval? (interval
#     honesty; target 0.50 / 0.90) -- the fraction of weeks it lands between the
#     corresponding quantiles.
#   - REVISION: how far the published median sits from the settled truth, as a
#     fraction of the truth -- signed (bias), absolute (typical move), a 5-95%
#     band, and the tail exceedance probabilities.

#' Evaluate a nowcast backtest: interval coverage + point-estimate revision
#'
#' Merges coverage (are the intervals honest?) and revision (how much will the
#' number still move?) into one per-group table. Coverage is computed straight
#' from the interval quantiles, so this needs no `scoringutils`.
#' @param backtest Output of [nowcast_backtest] (long quantile nowcasts; must
#'   include the 0.05/0.25/0.5/0.75/0.95 quantile levels).
#' @param truth Output of [nowcast_truth] (settled totals per reference week).
#' @param by Grouping columns for the summary (default "horizon").
#' @param thresholds Absolute-revision cut-offs to report the exceedance
#'   probability for (default 25\% and 50\%).
#' @returns One row per group: `n`, interval coverage (`coverage_50`,
#'   `coverage_90`), and the point-estimate revision (`median_signed` = bias,
#'   `median_abs`, `q05`/`q95` = the 5-95\% revision band, and `p_gt_<t>` for each
#'   threshold).
#' @export
nowcast_evaluate_v1 <- function(backtest, truth, by = "horizon",
                                thresholds = c(0.25, 0.5)) {
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

#' Recommend a nowcast model from a head-to-head comparison
#'
#' Ranks the methods in a [nowcast_compare] table by their mean score across
#' horizons (default the absolute revision -- the point estimate that settles
#' fastest) and audits a configured choice: it "meets" the recommendation when its
#' mean score is within `margin` of the best. Lets a pipeline keep a fixed
#' configured model while flagging when a candidate clearly beats it.
#' @param comparison A [nowcast_compare] output (per-horizon evaluations with a
#'   `method` column).
#' @param configured The method label currently in production.
#' @param metric Column to rank on, smaller = better. Default `"median_abs"`.
#' @param margin Relative tolerance: `configured` meets the recommendation when
#'   its mean metric <= best * (1 + margin). Default 0.05.
#' @returns A list: `configured`, `configured_score`, `recommended`,
#'   `recommended_score`, `meets` (logical), and `by_method` (a data.table of the
#'   per-method mean metric, ascending).
#' @export
nowcast_recommend_v1 <- function(comparison, configured, metric = "median_abs",
                                 margin = 0.05) {
  d <- data.table::as.data.table(comparison)
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
