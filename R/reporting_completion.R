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
# reporting_triangle_matrix() has already dropped every cell with delay >=
# max_delay_days, so `tot` is the row sum of the TRUNCATED matrix, and
# complete_by_md is the last cumulative fraction of that same total. It is
# therefore identically 1 (and pct_delay<max_delay_days-1> identically 100)
# whatever the real tail beyond the horizon is: it CANNOT detect reporting that
# dribbles in past max_delay_days. To look for a tail, re-run with a larger
# max_delay_days and compare mean_delay and the pct_delayD curve.
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

#' Empirical reporting-completion summary from a reporting triangle
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay_days Delay horizon in DAYS: delay day 0 to
#'   `max_delay_days - 1`. `max_delay_days = 35` is the 35 days that start on the
#'   reference week's Monday, and matches the 5 weekly delay columns of the
#'   pre-Date format.
#' @param delay_window Optional: use only settled weeks within roughly this many
#'   WEEKS (drift-aware). This one is weeks, not days, because it selects
#'   reference weeks and the reference axis is still an ISO week. `NULL` uses all
#'   settled weeks. Ignored for the shape of `period` stratification, which
#'   slices time itself.
#' @param period Time stratification of the settled weeks, by the calendar year
#'   or month of each week's Thursday. Choose `"all"` (one pooled curve,
#'   default), `"year"`, or `"month"` (one row per period). Use `"year"` or
#'   `"month"` to see whether completion time is trending up or down.
#' @returns One row per series, and per period when stratified. The columns are
#'   identity columns + `period` + `n_settled`, `mean_delay`, `complete_by_md`,
#'   and `pct_delay0`..`pct_delay<max_delay_days-1>`. There are exactly
#'   `max_delay_days` of those `pct_delayD` columns. Each one is the pooled
#'   \% of cases reported by the end of day reference Monday + D, the delay ECDF,
#'   no interpolation. `pct_delay0` is the reference week's own Monday.
#'   `mean_delay` is in DAYS. Every one of these is computed AFTER delays
#'   `>= max_delay_days` are discarded. They describe the cases that arrive
#'   within the horizon, not all eventual cases.
#' @section complete_by_md is always 1:
#' `complete_by_md` is the last cumulative fraction of a total that was itself
#' summed over the truncated delay axis. So it equals 1 for every series and every
#' period, and `pct_delay<max_delay_days-1>` equals 100. It does NOT measure
#' whether reporting continues past `max_delay_days`. To look for a tail, re-run
#' with a larger `max_delay_days` and compare `mean_delay` and the `pct_delayD`
#' curve.
#' @family reporting completion functions
#' @seealso \code{vignette("pipeline", package = "csalert")}, which runs this
#'   function on its synthetic triangle.
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
#' # one pooled curve over 21 delay days. This series reports on days 3, 10 and
#' # 17 after the reference Monday, so the curve steps at those three days.
#' rc <- reporting_completion_v1(tri, max_delay_days = 21)
#' rc[, .(n_settled, mean_delay, pct_delay3, pct_delay10, pct_delay17)]
#'
#' # there is one pct_delay column per delay day
#' sum(grepl("^pct_delay", names(rc)))
#'
#' # sliced by month, to expose drift in how fast reporting arrives
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

#' Reporting-completion trend: the delay curve by year and recent months
#'
#' Convenience over [reporting_completion_v1]: the completion curve sliced by calendar
#' `year` (all years) and by `month` (the most recent `n_months`, per series),
#' stacked with a `scope` column. One table that shows whether reporting is
#' speeding up or slowing down over time.
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay_days Delay horizon in DAYS. Passed straight to
#'   [reporting_completion_v1].
#' @param n_months Keep this many most-recent months per series. Default 12.
#' @returns A data.table: the [reporting_completion_v1] columns plus a `scope` column
#'   ("year"/"month"), the year rows followed by the last-`n_months` month rows.
#'   Empty when no series has enough settled data.
#' @family reporting completion functions
#' @seealso Neither package vignette covers this function;
#'   \code{vignette("pipeline", package = "csalert")} runs
#'   \code{\link{reporting_completion_v1}}, which this one wraps.
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
