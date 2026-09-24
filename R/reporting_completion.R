# reporting_completion_v1: the empirical reporting-delay summary of a triangle --
# "how long until a reference week's cases are (nearly) all in".
#
# From the SETTLED weeks (old enough to know their final total -- else the
# right-truncation makes recent weeks look more complete than they are), pool the
# cumulative fraction reported by each delay DAY, then read off: the mean delay in
# days, and the delay ECDF evaluated at each DISCRETE delay day -- pct_delayD = the
# pooled % of a reference week's cases in by the END of day (reference Monday + D).
# pct_delay0 is the reference week's own Monday. No interpolation: these are the
# step heights themselves.
#
# THE DELAY AXIS IS DAYS. max_delay_days = 35 gives 35 columns, pct_delay0 to
# pct_delay34, covering the 35 days that start on the reference week's Monday.
# The column count equals max_delay_days exactly.
#
# EVERY NUMBER HERE IS CONDITIONAL ON max_delay_days, INCLUDING complete_by_md.
# reporting_triangle_matrix() counts every report at delay >= max_delay_days in
# the last delay column, max_delay_days - 1. So `tot` is the row sum over every
# non-negative delay, and complete_by_md is the last cumulative fraction of that
# same total. It is identically 1, and pct_delay<max_delay_days-1> is
# identically 100, whatever the real tail is. The tail is in the last step:
# 100 - pct_delay<max_delay_days-2> is the share reported on delay day
# max_delay_days - 1 or later. mean_delay counts each of those reports at
# max_delay_days - 1, so it is a lower bound on the uncapped mean delay. A week
# settles at age max_delay_days - 1 days, and a later report can still arrive
# for it. To see the shape of the tail, re-run with a larger max_delay_days and
# compare mean_delay and the pct_delayD curve.
#
# `period` stratifies the settled weeks in time (by the week's Thursday) so a
# DRIFT in reporting speed is visible: one pooled curve hides a reporting system
# that is slowing down or speeding up; `"year"` / `"month"` give one curve per
# period so the trend in mean_delay is readable straight off the table.

# completion summary for one block of settled weeks (rows = reference weeks,
# cols = delay days 0..max_delay_days-1); NULL when too few non-empty weeks to
# trust.
.rc_summarise <- function(M) {
  tot <- rowSums(M)
  ok <- tot > 0
  if (sum(ok) < 3L) {
    return(NULL)
  }
  Mk <- M[ok, , drop = FALSE]
  # apply(, 1, cumsum) returns a MATRIX (delays x weeks) for >= 2 delay columns,
  # which t() puts back to weeks x delays -- but a VECTOR of length n_settled when
  # there is only one delay column, and t() then makes that 1 x n_settled. That
  # silently produced one pct_delay column per settled WEEK at max_delay_days = 1,
  # and a complete_by_md far below 1. With a single delay the cumulative sum is
  # the column itself, so take it directly.
  cum <- if (ncol(Mk) == 1L) Mk else t(apply(Mk, 1, cumsum))
  frac <- colSums(cum) / sum(tot[ok]) # pooled cumulative fraction by delay day
  incr <- c(frac[1], diff(frac))
  row <- data.table::data.table(
    n_settled = sum(ok),
    mean_delay = round(sum((seq_along(frac) - 1L) * incr), 2), # mean delay in DAYS
    complete_by_md = round(frac[length(frac)], 3)
  )
  # the delay ECDF read at each DISCRETE delay day: pct_delayD = pooled % of a
  # reference week's cases reported by the END of day (reference Monday + D), so
  # pct_delay0 is the reference week's own Monday. Indexed by delay day, 0-based,
  # to match max_delay_days and the triangle's own delay axis -- frac[i] is delay
  # day i - 1. No interpolation: these are the step heights themselves.
  for (i in seq_along(frac)) {
    row[[paste0("pct_delay", i - 1L)]] <- round(frac[i] * 100, 1)
  }
  return(row)
}

#' Measure how fast the counts of a reporting triangle arrive
#'
#' Pools the settled weeks of each series, and returns the share of cases
#' reported by each delay day, and the mean delay. Use it to choose
#' `max_delay_days`, and with `period` to see reporting speed up or slow down.
#'
#' A week is settled when its Monday is at least `max_delay_days - 1` days before
#' the as-of date. In each period, the function drops a week with a total of 0.
#' A period with fewer than 3 weeks left gets no row, and no warning.
#' @param triangle The `csfmt_reporting_triangle_v3` to measure.
#' @param max_delay_days The delay horizon in days, delay day 0 to
#'   `max_delay_days - 1`.
#' @param delay_window Use only the settled weeks of about this many recent weeks.
#'   It counts weeks, not days. `NULL` uses every settled week.
#' @param period `"all"` gives one pooled row. `"year"` and `"month"` give one row
#'   per calendar year or month of the Thursday of each week, so the year is the
#'   ISO year.
#' @returns A data.table with one row per series and period: the identity
#'   columns, `period`, `n_settled`, `mean_delay`, `complete_by_md`, and
#'   `pct_delay0` to `pct_delay<max_delay_days - 1>`.
#' * `n_settled`: the settled weeks with a total above 0.
#' * `mean_delay`: the mean delay in days over the pooled cases. A report at delay
#'   `max_delay_days` or later counts at `max_delay_days - 1`, so it is a lower
#'   bound.
#' * `pct_delayD`: the percentage of pooled cases reported by the end of day `D`
#'   from the reference Monday, with no interpolation. `pct_delay0` is the Monday
#'   itself.
#' @section complete_by_md is always 1:
#' `complete_by_md` is the last cumulative share of the total. So it is 1 for
#' every series and period, and `pct_delay<max_delay_days - 1>` is 100. It does
#' NOT show whether reporting continues after `max_delay_days`.
#'
#' The last column also holds every later delay. So
#' `100 - pct_delay<max_delay_days - 2>` is the share reported on the last day or
#' later. To see the tail, run it again with a larger `max_delay_days`, and
#' compare `mean_delay` and the `pct_delayD` curve.
#' @family reporting completion functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 3, which shows how to
#'   read each column.
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
#' # One pooled curve over 21 delay days. This series reports on days 3, 10 and
#' # 17 after the reference Monday, so the curve steps on those three days.
#' rc <- reporting_completion_v1(tri, max_delay_days = 21)
#' rc[, .(n_settled, mean_delay, pct_delay3, pct_delay10, pct_delay17)]
#'
#' # there is one pct_delay column per delay day
#' sum(grepl("^pct_delay", names(rc)))
#'
#' # sliced by month, to show a change in reporting speed
#' head(
#'   reporting_completion_v1(tri, max_delay_days = 21, period = "month")[,
#'     .(period, n_settled, mean_delay, pct_delay10)
#'   ],
#'   3
#' )
#' @export
reporting_completion_v1 <- function(
  triangle,
  max_delay_days,
  delay_window = NULL,
  period = c("all", "year", "month")
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_id <- NULL
  period <- match.arg(period)
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay_days)
  as_of <- attr(triangle, "as_of")
  id_cols <- attr(triangle, "id_cols")
  d_tri <- data.table::as.data.table(triangle)

  out <- list()
  for (tsid in names(rts)) {
    refs <- rts[[tsid]]$reference
    mat <- rts[[tsid]]$mat
    week_start <- isoyearweek_week_start(refs)
    # Age in DAYS, from the reference week's Monday to the as-of date. Both
    # sides are Dates, so this is a date subtraction and not a calendar lookup.
    age <- as.integer(as_of - week_start)
    keep <- age >= (max_delay_days - 1L)
    if (!is.null(delay_window)) {
      # delay_window is in WEEKS, so convert it before comparing against days
      keep <- keep & age < (delay_window * 7L + max_delay_days)
    }
    if (!any(keep)) {
      next
    }
    M <- mat[keep, , drop = FALSE]
    # period label per settled reference week. Year is the ISO year. For month we
    # need to pick which calendar month owns a week that straddles two: use the
    # week's midweek day (Thursday), the ISO-standard representative -- it is the
    # median of Mon-Sun, so the month with >= 4 of the week's 7 days always wins.
    # (This is the same Thursday rule ISO uses to assign the year, hence isoyear
    # itself, so format(thursday, "%Y") IS the ISO year.)
    thursday <- week_start[keep] + 3L
    per <- switch(
      period,
      all = rep("all", length(thursday)),
      year = format(thursday, "%Y"),
      month = format(thursday, "%Y-%m")
    )
    ids <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[1]
    for (pv in sort(unique(per))) {
      # one summary per period slice
      s <- .rc_summarise(M[per == pv, , drop = FALSE])
      if (is.null(s)) {
        next
      }
      out[[paste(tsid, pv)]] <- data.table::data.table(ids, period = pv, s)
    }
  }
  return(data.table::rbindlist(out, fill = TRUE))
}

#' Reporting speed by year and by recent month, in one table
#'
#' Stacks [reporting_completion_v1()] by year, and by month for the latest
#' `n_months` months of each series, so one table shows reporting speed up or slow
#' down.
#' @param triangle The `csfmt_reporting_triangle_v3` to measure.
#' @param max_delay_days The delay horizon in days.
#' @param n_months The number of latest months to keep for each series.
#' @returns A data.table with the columns of [reporting_completion_v1()] and
#'   `scope`, `"year"` or `"month"`, with the year rows first. It is empty when no
#'   series has enough settled weeks.
#' @family reporting completion functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 3.
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
#' tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
#' reporting_completion_trend_v1(tri, max_delay_days = 21, n_months = 6)[,
#'   .(scope, period, n_settled, mean_delay)]
#' @export
reporting_completion_trend_v1 <- function(
  triangle,
  max_delay_days,
  n_months = 12L
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  period <- scope <- NULL
  by_year <- reporting_completion_v1(triangle, max_delay_days, period = "year")
  by_month <- reporting_completion_v1(
    triangle,
    max_delay_days,
    period = "month"
  )
  if (nrow(by_year)) {
    by_year[, scope := "year"]
  }
  if (nrow(by_month)) {
    id_cols <- attr(triangle, "id_cols")
    data.table::setorder(by_month, period)
    by_month <- by_month[, utils::tail(.SD, n_months), by = id_cols] # last N months per series
    by_month[, scope := "month"]
  }
  return(data.table::rbindlist(list(by_year, by_month), fill = TRUE))
}
