# nowcast_censor / nowcast_truth / nowcast_backtest: the REPLAY mechanics behind
# the nowcast diagnostics.
#
# The reporting triangle already records, per cell, WHEN a count was reported --
# so we can reconstruct exactly what was known at any past DATE (`nowcast_censor`)
# without re-reading truncated raw data. Replaying an engine across a series of
# "as-of" dates (`nowcast_backtest`) and comparing to the eventually-settled totals
# (`nowcast_truth`) is how you tell whether a nowcast is any good. The scoring on
# top of a replay lives in nowcast_evaluate.R (`nowcast_evaluate_v1`).
#
# THE REPORTING AXIS IS A DATE. `as_of` is a Date, the delay horizon
# `max_delay_days` counts DAYS, and no function here looks a reporting value up
# in the ISO-week calendar. The reference axis is still an ISO week, so a
# `horizon` is still a whole number of weeks.
#
# The method contract is deliberately minimal: a nowcast method is a function
#   f(triangle) -> csfmt_ensemble_v3
# with all of ITS parameters baked in (e.g. via a closure). That keeps engines
# with different signatures (n_sim, priors, ...) composable through one interface.

#' Censor a reporting triangle to what was known "as of" a past date
#'
#' Keeps only cells reported on or before `as_of` and rebuilds the triangle. Its
#' as-of boundary and delay structure are then exactly what an engine would have
#' seen on that date. The basis for replay-based backtesting.
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param as_of A `Date`. Cells reported after it are dropped. A character, a
#'   number, a factor and an `IDate` each error. The check is strict because R
#'   reads `reporting date <= as_of` from the type of `as_of`. A number is a day
#'   count since 1970-01-01, so `as_of = 18262` censors to 2020-01-01 and
#'   reports nothing wrong. A character goes through `as.Date()`, so `"2020-11"`
#'   errors inside `charToDate()` with a message that never names `as_of`.
#' @returns A `csfmt_reporting_triangle_v3` censored to `as_of`.
#' @family nowcast diagnostics
#' @seealso \code{vignette("pipeline", package = "csalert")} calls this
#'   function directly in its validation stage, to rebuild what was known on an
#'   earlier date. \code{\link{nowcast_evaluate_v1}} censors for you when you do
#'   not need the censored triangle itself.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' # rewind to what was known nine weeks earlier
#' past <- nowcast_censor(tri, as_of = as.Date("2023-01-02") + 7 * 30 + 6)
#' c(now = attr(tri, "as_of"), then = attr(past, "as_of"))
#' c(rows_now = nrow(tri), rows_then = nrow(past))
#' @export
nowcast_censor <- function(triangle, as_of) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  # Strict on the class, not on inheritance, exactly as the constructor is. R
  # reads `reporting date <= as_of` from the type of as_of, and each wrong type
  # fails differently. Measured on the pre-assertion tree, 2026-09-22: 18262 is
  # a day count since 1970-01-01, so it censored to 2020-01-01 and reported
  # nothing wrong; "2020-11" went through as.Date() and errored inside
  # charToDate(), with a message that never named as_of; a factor raised an
  # "Incompatible methods" warning first. One strict check replaces all three.
  if (!identical(class(as_of), "Date")) {
    stop(
      "`as_of` must be a Date, not ",
      paste(class(as_of), collapse = "/"),
      call. = FALSE
    )
  }
  rep_col <- attr(triangle, "reporting_col")
  ref_col <- attr(triangle, "reference_col")
  val_col <- attr(triangle, "value_col")
  d <- data.table::as.data.table(triangle)
  d <- d[get(rep_col) <= as_of]
  if (!nrow(d)) {
    stop("nothing reported on or before ", format(as_of), call. = FALSE)
  }
  return(csfmt_reporting_triangle_v3(
    d,
    id_cols = attr(triangle, "id_cols"),
    reference_col = ref_col,
    reporting_col = rep_col,
    value_col = val_col
  ))
}

#' The settled (eventually-observed) total per reference week
#'
#' Sums each reference week's counts over every non-negative delay, the quantity
#' a nowcast is trying to predict. A report at delay `max_delay_days` or later
#' counts in the last delay day, `max_delay_days - 1`, so it is inside this
#' total. Keeps only the weeks old enough to be settled. A settled week's Monday
#' is at least `max_delay_days - 1` days before the triangle's as-of date. That
#' bound is one lower than it may read. With `max_delay_days = 21`, the newest
#' settled week starts 20 days before the as-of date, not 21. A settled week is
#' not final. A report that arrives after the as-of date has a delay of
#' `max_delay_days` or more, and it still adds to the week's total.
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param max_delay_days Delay horizon in DAYS: delay day 0 to
#'   `max_delay_days - 1`. `max_delay_days = 35` is the 35 days that start on the
#'   reference week's Monday. It matches the 5 weekly delay columns of the
#'   pre-Date format.
#' @returns A data.table `reference`, `truth`.
#' @family nowcast diagnostics
#' @seealso \code{vignette("pipeline", package = "csalert")} calls this
#'   function directly in its validation stage to obtain settled truth.
#'   \code{\link{nowcast_evaluate_v1}} calls it for you when you only want the
#'   scores.
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' truth <- nowcast_truth(tri, max_delay_days = 21)
#'
#' # the newest weeks are missing: they are not settled yet, so they have no
#' # truth to be scored against
#' tail(truth, 3)
#' c(reference_weeks = 40L, settled = nrow(truth))
#' @export
nowcast_truth <- function(triangle, max_delay_days) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay_days)
  if (length(rts) != 1L) {
    stop(
      "nowcast_truth expects a single-series triangle; filter to one series first",
      call. = FALSE
    )
  }
  refs <- rts[[1]]$reference
  total <- rowSums(rts[[1]]$mat)
  # Age in DAYS, from the reference week's Monday to the as-of date. A week is
  # settled once every delay day inside the horizon could have been reported,
  # which is age >= max_delay_days - 1. Both sides are Dates, so this is a date
  # subtraction and not a calendar lookup.
  age_days <- as.integer(attr(triangle, "as_of") - isoyearweek_week_start(refs))
  settled <- age_days >= (max_delay_days - 1L)
  return(data.table::data.table(reference = refs, truth = total)[settled])
}

# The reference weeks behind the default as-of set. They run from the first to
# the last week with a report at delay day 0 to max_delay_days - 1. This is the
# reference axis reporting_triangle_matrix() built before a late report counted
# in its last column. The matrix axis now also reaches a week whose only reports
# are late. On a bulk load of old weeks that added one as-of date per old week,
# on which nothing had been reported yet. Measured on a synthetic bulk load: 52
# "nothing reported" warnings, where this set gives 0.
.bt_default_refs <- function(triangle, max_delay_days) {
  ref_col <- attr(triangle, "reference_col")
  rep_col <- attr(triangle, "reporting_col")
  refs <- triangle[[ref_col]]
  delay <- as.integer(triangle[[rep_col]] - isoyearweek_week_start(refs))
  in_horizon <- refs[!is.na(delay) & delay >= 0L & delay < max_delay_days]
  # No report inside the horizon gives an empty set. Without this return, min()
  # and max() of the empty vector warned and returned NA, and NA:NA errored with
  # "NA/NaN argument". nowcast_backtest() then replays no as-of date.
  if (!length(in_horizon)) {
    return(character(0))
  }
  all_weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i1 <- match(min(in_horizon), all_weeks)
  i2 <- match(max(in_horizon), all_weeks)
  return(all_weeks[i1:i2])
}

# One as_of date of the backtest: run the method on the censored triangle,
# collapse it, and emit one row per horizon and quantile level. Returns an
# empty list when the method fails or the horizons are not covered.
.bt_one_as_of <- function(
  triangle,
  method,
  as_of,
  horizons,
  probs,
  measure,
  seed
) {
  .horizon <- NULL
  rows <- list()
  if (!is.null(seed)) {
    # The reproducibility key is the as-of DATE's day number (days since
    # 1970-01-01). That is one integer per date and it never changes, so a given
    # cell is reproducible whatever order the as-of dates arrive in.
    set.seed(seed + as.integer(as_of))
  }
  ens <- tryCatch(
    method(nowcast_censor(triangle, as_of)),
    error = function(e) {
      warning("as_of ", format(as_of), ": ", conditionMessage(e), call. = FALSE)
      return(NULL)
    }
  )
  if (is.null(ens)) {
    return(list())
  }
  q <- ens_collapse(ens, probs = probs)
  # Horizon is still a whole number of WEEKS: the days from the reference week's
  # Monday to the as-of date, divided down. The as-of date may fall on any
  # weekday, and %/% 7 puts it on the right week either way.
  q[,
    .horizon := as.integer(
      as_of - isoyearweek_week_start(get("isoyearweek"))
    ) %/%
      7L
  ]
  q <- q[.horizon %in% horizons]
  if (!nrow(q)) {
    return(list())
  }
  for (p in probs) {
    col <- csfmt_var(measure, q = p)
    if (!col %in% names(q)) {
      next
    }
    rows[[length(rows) + 1L]] <- data.table::data.table(
      reference = q$isoyearweek,
      as_of = as_of,
      horizon = q$.horizon,
      quantile_level = p,
      predicted = q[[col]]
    )
  }
  return(rows)
}


#' Replay a nowcast method across as-of dates (backtest)
#'
#' For each `as_of` date, censor the triangle to what was known then, run the
#' method, collapse to quantiles, and collect the nowcast for the reference weeks
#' at the requested horizons (horizon = whole weeks between the reference week
#' and the as-of date). An as-of date whose method call errors (e.g. too little
#' history) is skipped with a warning rather than aborting the sweep.
#' @param triangle A `csfmt_reporting_triangle_v3` (single series).
#' @param method A function `f(triangle) -> csfmt_ensemble_v3` (params baked in).
#' @param as_of_weeks A `Date` vector of as-of dates to replay. Default: the last
#'   day of each reference week, after a burn-in of `max_delay_days` rounded up
#'   to whole weeks. The weeks run from the first to the last week with a report
#'   at delay day 0 to `max_delay_days - 1`. A week whose only reports are later
#'   does not extend that range. With no report inside the horizon the default
#'   set is empty, and the function returns an empty data.table. The name says
#'   weeks because the replay cadence is weekly. The values are dates.
#' @param max_delay_days Delay horizon in DAYS. Sets the default as-of set and
#'   the burn-in.
#' @param horizons Integer weeks-back to keep (0 = the as-of week itself).
#' @param probs Quantile probabilities to extract.
#' @param measure Ensemble measure to score; default the numerator's nowcast.
#' @param seed Optional integer base seed. Each as-of is seeded as
#'   `seed + as.integer(as_of)`, the as-of date's day number, so a given cell is
#'   reproducible regardless of the as-of list order. The nowcast draws for date
#'   D depend only on `seed` and `D`.
#' @returns A long data.table: `reference`, `as_of`, `horizon`, `quantile_level`,
#'   `predicted`. `as_of` is a `Date`.
#' @family nowcast diagnostics
#' @seealso \code{vignette("pipeline", package = "csalert")} runs this
#'   function in its validation stage. \code{\link{nowcast_evaluate_v1}} wraps it
#'   and scores the result; use this one directly when you want the raw replayed
#'   quantiles.
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' # a method is f(triangle) -> ensemble, with its own parameters baked in
#' method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)
#'
#' # Replay 19 as-of dates, each the Sunday that ends a reference week. This
#' # window is a runtime choice, not a fitting boundary: the engine needs only
#' # three settled training rows, and with fewer it returns the observed totals
#' # rather than failing. Leaving `as_of_weeks` NULL replays every week after the
#' # burn-in, which is slower.
#' bt <- nowcast_backtest(
#'   tri, method,
#'   max_delay_days = 21,
#'   as_of_weeks = as.Date("2023-01-02") + 7 * (20:38) + 6,
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
  max_delay_days,
  horizons = 1:2,
  probs = c(.025, .05, .1, .25, .5, .75, .9, .95, .975),
  measure = NULL,
  seed = NULL
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  .horizon <- NULL
  stopifnot(
    inherits(triangle, "csfmt_reporting_triangle_v3"),
    is.function(method)
  )
  if (data.table::uniqueN(triangle$time_series_id) > 1L) {
    stop(
      "nowcast_backtest expects a single-series triangle; filter to one series first",
      call. = FALSE
    )
  }
  if (is.null(measure)) {
    measure <- csfmt_var(attr(triangle, "value_col"), role = "nowcasted")
  }

  if (is.null(as_of_weeks)) {
    # The default as-of set is built from DATES. The reference axis is no longer
    # the reporting axis, so a reference week cannot stand in for an as-of date.
    # Replay as of the last day of each reference week, which is what "as of
    # week W" used to mean.
    refs <- .bt_default_refs(triangle, max_delay_days)
    week_end <- isoyearweek_week_start(refs) + 6L
    burn_in <- as.integer(ceiling(max_delay_days / 7))
    as_of_weeks <- utils::tail(week_end, max(0L, length(week_end) - burn_in))
  }
  # Without this the censor error is caught by .bt_one_as_of and demoted to a
  # warning, so a character as_of_weeks would return an empty table.
  if (!identical(class(as_of_weeks), "Date")) {
    stop(
      "`as_of_weeks` must be a Date vector, not ",
      paste(class(as_of_weeks), collapse = "/"),
      call. = FALSE
    )
  }

  out <- list()
  # Index the vector. `for (as_of in as_of_weeks)` strips the Date class and
  # hands the body a bare numeric, which then compares as a number against a
  # Date column.
  for (i in seq_along(as_of_weeks)) {
    out <- c(
      out,
      .bt_one_as_of(
        triangle,
        method,
        as_of_weeks[i],
        horizons,
        probs,
        measure,
        seed
      )
    )
  }
  return(data.table::rbindlist(out))
}
