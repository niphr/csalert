# nowcast_evaluate_v1: replay nowcast method(s) over a triangle and score each on
# interval coverage + point-estimate revision, in ONE per-horizon table. Pass one
# method or a named list; a shared seed pairs them by as-of week.
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
.evaluate_backtest <- function(
  backtest,
  truth,
  by = "horizon",
  thresholds = c(0.25, 0.5)
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  hi50 <- hi90 <- in50 <- in90 <- lo50 <- lo90 <- med <- NULL
  bt <- data.table::as.data.table(backtest)
  if (!nrow(bt)) {
    stop("empty backtest: nothing to evaluate", call. = FALSE)
  }
  d <- merge(bt, data.table::as.data.table(truth), by = "reference")
  d <- d[is.finite(truth)]
  if (!nrow(d)) {
    stop(
      "no overlap between backtest reference weeks and settled truth",
      call. = FALSE
    )
  }

  # One row per forecast unit (reference x as_of x horizon) with the quantiles
  # needed. `as_of` is a Date and it is a merge key here, so it has to survive
  # every merge below and any group-by the caller asks for through `by`.
  # data.table keeps the Date class through both, and the tests pin that.
  unit <- intersect(c("reference", "as_of", "horizon"), names(d))
  qcol <- function(p, nm) {
    # NSE column names, declared so R CMD check does not read them as undefined globals
    quantile_level <- NULL
    x <- d[quantile_level == p, c(unit, "predicted"), with = FALSE]
    return(data.table::setnames(x, "predicted", nm)[])
  }
  truth_u <- unique(d[, c(unit, "truth"), with = FALSE])
  m <- Reduce(
    function(a, b) merge(a, b, by = unit),
    list(
      truth_u,
      qcol(0.05, "lo90"),
      qcol(0.95, "hi90"),
      qcol(0.25, "lo50"),
      qcol(0.75, "hi50"),
      qcol(0.5, "med")
    )
  )
  if (!nrow(m)) {
    stop(
      "backtest is missing the 0.05, 0.25, 0.5, 0.75 and 0.95 quantiles needed to evaluate",
      call. = FALSE
    )
  }

  m[, `:=`(
    in90 = truth >= lo90 & truth <= hi90,
    in50 = truth >= lo50 & truth <= hi50
  )]
  m[truth > 0, rel := (med - truth) / truth] # relative revision (undefined at truth 0)

  return(m[,
    {
      r <- rel[is.finite(rel)]
      a <- abs(r)
      has <- length(r) > 0
      c(
        list(
          n = .N,
          coverage_50 = round(mean(in50), 3),
          coverage_90 = round(mean(in90), 3),
          median_signed = if (has) round(stats::median(r), 4) else NA_real_,
          median_abs = if (has) round(stats::median(a), 4) else NA_real_,
          q05 = if (has) {
            round(stats::quantile(r, 0.05, names = FALSE), 4)
          } else {
            NA_real_
          },
          q95 = if (has) {
            round(stats::quantile(r, 0.95, names = FALSE), 4)
          } else {
            NA_real_
          }
        ),
        stats::setNames(
          lapply(thresholds, function(t) {
            if (has) return(round(mean(a > t), 4)) else return(NA_real_)
          }),
          paste0("p_gt_", thresholds * 100)
        )
      )
    },
    by = by
  ])
}

# The weighted interval score of one forecast unit (Bracher et al. 2021). The
# central intervals are the quantile pairs present at levels p and 1 - p, p < 0.5.
.wis_unit <- function(level, predicted, y) {
  lev <- round(level, 8)
  m <- predicted[lev == 0.5]
  if (length(m) != 1L) {
    return(NA_real_)
  }
  p <- lev[lev < 0.5 & round(1 - lev, 8) %in% lev]
  l <- predicted[match(p, lev)]
  u <- predicted[match(round(1 - p, 8), lev)]
  alpha <- 2 * p
  is_alpha <- (u - l) +
    (2 / alpha) * (l - y) * (y < l) +
    (2 / alpha) * (y - u) * (y > u)
  return((0.5 * abs(y - m) + sum(alpha / 2 * is_alpha)) / (length(p) + 0.5))
}

#' Score replayed nowcast quantiles against the settled truth
#'
#' Scores a backtest from [nowcast_backtest()] against the truth from
#' [nowcast_truth()]. It adds the weighted interval score and a 95% interval
#' summary to the coverage and revision columns of [nowcast_evaluate_v1()].
#'
#' A forecast unit is one reference week at one as-of date and horizon. The
#' function scores only the units that have a finite truth and the 0.05, 0.25,
#' 0.5, 0.75 and 0.95 quantiles.
#'
#' The weighted interval score (WIS) follows Bracher et al. (2021). For a unit
#' with truth `y` and median `m`:
#'
#' ```
#' WIS  = (0.5 * |y - m| + sum_k (alpha_k / 2) * IS_k) / (K + 0.5)
#' IS_k = (u - l) + (2 / alpha_k) * (l - y) * 1{y < l} + (2 / alpha_k) * (y - u) * 1{y > u}
#' ```
#'
#' The sum is over the `K` central intervals from the quantile pairs at levels
#' `p` and `1 - p`, with `p < 0.5`. Interval `k` is from `l` to `u`, and
#' `alpha_k = 2 * p`.
#' @param backtest A data.table from [nowcast_backtest()], with the columns
#'   `reference`, `quantile_level` and `predicted`, and optionally `as_of` and
#'   `horizon`.
#' @param truth A data.table from [nowcast_truth()], with the columns
#'   `reference` and `truth`.
#' @param by The columns to group the scores by.
#' @param thresholds The absolute revisions for the `p_gt_<t>` columns.
#' @returns A data.table with one row per group. It has the columns of
#'   [nowcast_evaluate_v1()] except `method`, and these columns:
#' * `wis`: the mean WIS over the units,
#' * `wis_log`: the mean WIS after `log1p()` of each quantile and of the truth,
#' * `coverage_95`: the share of truths from the 0.025 to the 0.975 quantile,
#' * `width_95_rel_median`: the median over the units of
#'   `(q0.975 - q0.025) / max(truth, 1)`.
#'
#' `coverage_95` and `width_95_rel_median` are `NA` for a group where a unit has
#' no 0.025 or no 0.975 quantile.
#' @references Bracher J, Ray EL, Gneiting T, Reich NG (2021). Evaluating
#'   epidemic forecasts in an interval format. PLOS Computational Biology 17(2):
#'   e1008618. \doi{10.1371/journal.pcbi.1008618}
#' @examples
#' truth <- data.table::data.table(reference = "2024-01", truth = 100)
#' backtest <- data.table::data.table(
#'   reference = "2024-01", horizon = 0L,
#'   quantile_level = c(0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975),
#'   predicted = c(60, 70, 85, 95, 105, 120, 130))
#' nowcast_score_v1(backtest, truth)
#' @export
nowcast_score_v1 <- function(
  backtest,
  truth,
  by = "horizon",
  thresholds = c(0.25, 0.5)
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  quantile_level <- predicted <- lo95 <- hi95 <- wis <- wis_log <- NULL
  coverage_95 <- width_95_rel_median <- i.wis <- i.wis_log <- NULL
  i.coverage_95 <- i.width_95_rel_median <- NULL
  ev <- .evaluate_backtest(backtest, truth, by = by, thresholds = thresholds)

  # The same units that .evaluate_backtest scores: a finite truth and the five
  # quantiles it needs.
  d <- merge(
    data.table::as.data.table(backtest),
    data.table::as.data.table(truth),
    by = "reference"
  )
  d <- d[is.finite(truth)]
  unit <- intersect(c("reference", "as_of", "horizon"), names(d))
  need <- c(0.05, 0.25, 0.5, 0.75, 0.95)
  u <- d[,
    {
      lev <- round(quantile_level, 8)
      y <- truth[1L]
      list(
        truth = y,
        ok = all(need %in% lev),
        wis = .wis_unit(quantile_level, predicted, y),
        wis_log = .wis_unit(quantile_level, log1p(predicted), log1p(y)),
        lo95 = if (0.025 %in% lev) predicted[lev == 0.025][1L] else NA_real_,
        hi95 = if (0.975 %in% lev) predicted[lev == 0.975][1L] else NA_real_
      )
    },
    by = unit
  ]
  u <- u[u$ok]
  s <- u[,
    list(
      wis = mean(wis),
      wis_log = mean(wis_log),
      coverage_95 = round(mean(truth >= lo95 & truth <= hi95), 3),
      width_95_rel_median = stats::median((hi95 - lo95) / pmax(truth, 1))
    ),
    by = by
  ]
  ev[
    s,
    on = by,
    `:=`(
      wis = i.wis,
      wis_log = i.wis_log,
      coverage_95 = i.coverage_95,
      width_95_rel_median = i.width_95_rel_median
    )
  ]
  return(ev[])
}

#' Score nowcast methods on interval coverage and revision
#'
#' Replays each method with [nowcast_backtest()], and scores every nowcast against
#' the settled truth from [nowcast_truth()]. It returns a row for each horizon and
#' method.
#'
#' The revision is `(median - truth) / truth`, over the weeks with a truth above
#' 0. Every score is a measurement on the replayed weeks, not a property of a
#' method. The methods replay the same as-of dates with the same `seed`, so they
#' are paired by forecast. That does not give common random numbers, which would
#' also need the methods to use their random numbers in the same way.
#' @param triangle A `csfmt_reporting_triangle_v3` with one series.
#' @param methods One method, or a named list of methods. A method takes a
#'   triangle and returns a `csfmt_ensemble_v3`. One method gets the name
#'   `"method"`.
#' @param max_delay_days The delay horizon in days.
#' @param as_of_weeks,horizons,probs,seed Passed to [nowcast_backtest()]. `probs`
#'   MUST include 0.05, 0.25, 0.5, 0.75 and 0.95.
#' @param by The columns to group the scores by.
#' @param thresholds The absolute revisions for the `p_gt_<t>` columns.
#' @returns A data.table with one row per group and method:
#' * `n`: the number of scored forecasts,
#' * `coverage_50`, `coverage_90`: the share of truths from the 0.25 to the 0.75
#'   quantile, and from the 0.05 to the 0.95 quantile,
#' * `median_signed`, `median_abs`, `q05`, `q95`: the median revision, the median
#'   absolute revision, and the 5% and 95% quantiles of the revision,
#' * `p_gt_<t>`: the share of absolute revisions above each threshold, such as
#'   `p_gt_25` for 0.25,
#' * `wis`, `wis_log`, `coverage_95`, `width_95_rel_median`: the weighted
#'   interval score and the 95% interval summary from [nowcast_score_v1()],
#' * `method`.
#'
#' A method with no nowcast gives a warning and no rows.
#' @family nowcast diagnostics
#' @seealso `vignette("pipeline", package = "csalert")`, stage 2, which explains
#'   how to read each column.
#' @examples
#' # a small reporting triangle: 30 weeks, each reported 3, 10 and 17 days
#' # after its Monday
#' monday <- as.Date("2023-01-02") + 7 * rep(0:29, each = 3)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 30),
#'   numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
#' tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
#'
#' # one method
#' nowcast_evaluate_v1(tri, function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay_days = 21),
#'                     max_delay_days = 21, horizons = 0:2, seed = 1)
#' # a named list of methods, with a `method` column in the result
#' nowcast_evaluate_v1(tri, max_delay_days = 21, horizons = 0:2, seed = 1, methods = list(
#'   passthrough = function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay_days = 21)))
#' @export
nowcast_evaluate_v1 <- function(
  triangle,
  methods,
  max_delay_days,
  as_of_weeks = NULL,
  horizons = 1:2,
  probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
  by = "horizon",
  thresholds = c(0.25, 0.5),
  seed = NULL
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  method <- NULL
  if (is.function(methods)) {
    methods <- list(method = methods)
  } # single -> one-element menu
  stopifnot(is.list(methods), length(methods) > 0, !is.null(names(methods)))
  truth <- nowcast_truth(triangle, max_delay_days)
  out <- list()
  for (nm in names(methods)) {
    bt <- nowcast_backtest(
      triangle,
      methods[[nm]],
      as_of_weeks = as_of_weeks,
      max_delay_days = max_delay_days,
      horizons = horizons,
      probs = probs,
      seed = seed
    )
    if (!nrow(bt)) {
      warning("method '", nm, "' produced no nowcasts", call. = FALSE)
      next
    }
    ev <- nowcast_score_v1(bt, truth, by = by, thresholds = thresholds)
    ev[, method := nm]
    out[[nm]] <- ev
  }
  return(data.table::rbindlist(out, fill = TRUE))
}
