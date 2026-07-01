# nowcast_revision: how much a nowcast's POINT estimate (median) still moves as a
# reference week matures -- the scale-free, human-readable complement to coverage.
#
# coverage asks "is the interval honest?"; revision asks "how far is the number I
# publish today from where it will end up?". Because it is a relative quantity
# (fraction of the settled truth) it is comparable across indicators of wildly
# different size -- unlike WIS, which is in case units.
#
# From a replay (nowcast_backtest) + settled truth (nowcast_truth): for each
# reference week take the median nowcast at each maturity (horizon) and compare to
# its settled total. rel = (median - truth) / truth: signed, so + means the
# nowcast sat ABOVE the eventual truth (a systematic sign = bias worth fixing).
# Summarised by horizon into: the typical signed revision (bias), the typical
# absolute revision, a 5-95% band (the "funnel"), and the tail probabilities
# ("how often does today's number still move by >25% / >50%?").

#' Point-estimate revision of a nowcast backtest, by horizon
#' @param backtest Output of [nowcast_backtest] (long quantile nowcasts).
#' @param truth Output of [nowcast_truth] (settled totals per reference week).
#' @param by Grouping columns for the summary (default "horizon").
#' @param thresholds Absolute-revision cut-offs to report the exceedance
#'   probability for (default 25\% and 50\%).
#' @returns One row per group: `n`, `median_signed` (bias), `median_abs`,
#'   `q05`/`q95` (the 5-95\% revision band), and `p_gt_<t>` for each threshold.
#' @export
nowcast_revision <- function(backtest, truth, by = "horizon",
                             thresholds = c(0.25, 0.5)) {
  bt <- data.table::as.data.table(backtest)
  if (!nrow(bt)) stop("empty backtest: nothing to measure revision on")
  med <- bt[quantile_level == 0.5]
  if (!nrow(med)) stop("backtest has no median (quantile_level == 0.5)")
  d <- merge(med, data.table::as.data.table(truth), by = "reference")
  d <- d[is.finite(truth) & truth > 0]              # relative revision undefined at truth 0
  if (!nrow(d)) stop("no settled truth > 0 to compute relative revision against")
  d[, rel := (predicted - truth) / truth]           # signed: + = nowcast above settled truth

  summ <- d[, {
    a <- abs(rel)
    c(list(n             = .N,
           median_signed = round(stats::median(rel), 4),
           median_abs    = round(stats::median(a), 4),
           q05           = round(stats::quantile(rel, 0.05, names = FALSE), 4),
           q95           = round(stats::quantile(rel, 0.95, names = FALSE), 4)),
      stats::setNames(lapply(thresholds, function(t) round(mean(a > t), 4)),
                      paste0("p_gt_", thresholds * 100)))
  }, by = by]
  summ[]
}
