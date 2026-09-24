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
    ev <- .evaluate_backtest(bt, truth, by = by, thresholds = thresholds)
    ev[, method := nm]
    out[[nm]] <- ev
  }
  return(data.table::rbindlist(out, fill = TRUE))
}
