# reporting_completion_v1: the empirical reporting-delay summary of a triangle --
# "how long until a reference week's cases are (nearly) all in".
#
# From the SETTLED weeks (old enough to know their final total -- else the
# right-truncation makes recent weeks look more complete than they are), pool the
# cumulative fraction reported by each delay, then read off: the mean delay, and
# the delay ECDF evaluated at each DISCRETE delay -- pct_delayD = the pooled % of a
# reference week's cases in by the END of week (reference + D). pct_delay0 is the
# reference week itself. No interpolation: these are the step heights themselves.
#
# EVERY NUMBER HERE IS CONDITIONAL ON max_delay, INCLUDING complete_by_md.
# reporting_triangle_matrix() has already dropped every cell with delay >=
# max_delay, so `tot` is the row sum of the TRUNCATED matrix, and complete_by_md
# is the last cumulative fraction of that same total. It is therefore identically
# 1 (and pct_delay<max_delay-1> identically 100) whatever the real tail beyond the
# horizon is: it CANNOT detect reporting that dribbles in past max_delay. To look
# for a tail, re-run with a larger max_delay and compare mean_delay and the
# pct_delayD curve.
#
# `period` stratifies the settled weeks in time (by the week's Thursday) so a
# DRIFT in reporting speed is visible: one pooled curve hides a reporting system
# that is slowing down or speeding up; `"year"` / `"month"` give one curve per
# period so the trend in mean_delay is readable straight off the table.

#' Empirical reporting-completion summary from a reporting triangle
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay Delay horizon in weeks.
#' @param delay_window Optional: use only settled weeks within roughly this many
#'   weeks (drift-aware). `NULL` uses all settled weeks. Ignored for the shape of
#'   `period` stratification, which slices time itself.
#' @param period Time stratification of the settled weeks, by the calendar year
#'   or month of each week's Thursday. Choose `"all"` (one pooled curve,
#'   default), `"year"`, or `"month"` (one row per period). Use `"year"` or
#'   `"month"` to see whether completion time is trending up or down.
#' @returns One row per series, and per period when stratified. The columns are
#'   identity columns + `period` + `n_settled`, `mean_delay`, `complete_by_md`,
#'   and `pct_delay0`..`pct_delay<max_delay-1>`. Each `pct_delayD` is the pooled
#'   \% of cases reported by the end of week reference + D -- the delay ECDF, no
#'   interpolation. `pct_delay0`
#'   is the reference week itself, NOT the week after. Every one of these is
#'   computed AFTER delays `>= max_delay` are discarded. They describe
#'   the cases that arrive within the horizon, not all eventual cases.
#' @section complete_by_md is always 1:
#' `complete_by_md` is the last cumulative fraction of a total that was itself
#' summed over the truncated delay axis. So it equals 1 for every series and every
#' period, and `pct_delay<max_delay-1>` equals 100. It does NOT measure whether
#' reporting continues past `max_delay`. To look for a tail, re-run with a larger
#' `max_delay` and compare `mean_delay` and the `pct_delayD` curve.
#' @family reporting completion functions
#' @seealso \code{vignette("pipeline", package = "csalert")}, which runs this
#'   function on its synthetic triangle.
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
#' # one pooled curve: pct_delay0 is the share in during the reference week itself
#' reporting_completion_v1(tri, max_delay = 3)
#'
#' # sliced by month, to expose drift in how fast reporting arrives
#' head(reporting_completion_v1(tri, max_delay = 3, period = "month"), 3)
#' @export
reporting_completion_v1 <- function(
  triangle,
  max_delay,
  delay_window = NULL,
  period = c("all", "year", "month")
) {
  period <- match.arg(period)
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay)
  dbi <- cstime::dates_by_isoyearweek
  weeks <- dbi$isoyearweek
  as_of_i <- match(attr(triangle, "as_of"), weeks)
  id_cols <- attr(triangle, "id_cols")
  d_tri <- data.table::as.data.table(triangle)

  # period label per isoyearweek. Year is just the ISO year. For month we need
  # to pick which calendar month owns a week that straddles two: use the week's
  # midweek day (Thursday), the ISO-standard representative -- it is the median of
  # Mon-Sun, so the month with >= 4 of the week's 7 days always wins. (This is the
  # same Thursday rule ISO uses to assign the year, hence isoyear itself.)
  plabel <- switch(
    period,
    all = rep("all", length(weeks)),
    year = as.character(dbi$isoyear),
    month = format(dbi$thu, "%Y-%m")
  ) # dbi$thu = the week's midweek day

  # completion summary for one block of settled weeks (rows = reference weeks,
  # cols = delays 0..max_delay-1); NULL when too few non-empty weeks to trust.
  summarise <- function(M) {
    tot <- rowSums(M)
    ok <- tot > 0
    if (sum(ok) < 3L) {
      return(NULL)
    }
    Mk <- M[ok, , drop = FALSE]
    # apply(, 1, cumsum) returns a MATRIX (delays x weeks) for >= 2 delay columns,
    # which t() puts back to weeks x delays -- but a VECTOR of length n_settled when
    # there is only one delay column, and t() then makes that 1 x n_settled. That
    # silently produced one pct_delay column per settled WEEK at max_delay = 1, and a
    # complete_by_md far below 1. With a single delay the cumulative sum is the
    # column itself, so take it directly.
    cum <- if (ncol(Mk) == 1L) Mk else t(apply(Mk, 1, cumsum))
    frac <- colSums(cum) / sum(tot[ok]) # pooled cumulative fraction by delay
    incr <- c(frac[1], diff(frac))
    row <- data.table::data.table(
      n_settled = sum(ok),
      mean_delay = round(sum((seq_along(frac) - 1L) * incr), 2), # mean delay in weeks
      complete_by_md = round(frac[length(frac)], 3)
    )
    # the delay ECDF read at each DISCRETE delay: pct_delayD = pooled % of a
    # reference week's cases reported by the END of week (reference + D), so
    # pct_delay0 is the reference week itself. Indexed by delay, 0-based, to match
    # max_delay and the triangle's own delay axis -- frac[i] is delay i - 1. No
    # interpolation: these are the step heights themselves.
    for (i in seq_along(frac)) {
      row[[paste0("pct_delay", i - 1L)]] <- round(frac[i] * 100, 1)
    }
    row
  }

  out <- list()
  for (tsid in names(rts)) {
    refs <- rts[[tsid]]$reference
    mat <- rts[[tsid]]$mat
    age <- as_of_i - match(refs, weeks)
    keep <- age >= (max_delay - 1L)
    if (!is.null(delay_window)) {
      keep <- keep & age < (delay_window + max_delay)
    }
    if (!any(keep)) {
      next
    }
    M <- mat[keep, , drop = FALSE]
    per <- plabel[match(refs[keep], weeks)]
    ids <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[1]
    for (pv in sort(unique(per))) {
      # one summary per period slice
      s <- summarise(M[per == pv, , drop = FALSE])
      if (is.null(s)) {
        next
      }
      out[[paste(tsid, pv)]] <- data.table::data.table(ids, period = pv, s)
    }
  }
  data.table::rbindlist(out, fill = TRUE)
}

#' Reporting-completion trend: the delay curve by year and recent months
#'
#' Convenience over [reporting_completion_v1]: the completion curve sliced by calendar
#' `year` (all years) and by `month` (the most recent `n_months`, per series),
#' stacked with a `scope` column. One table that shows whether reporting is
#' speeding up or slowing down over time.
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay Delay horizon in weeks.
#' @param n_months Keep this many most-recent months per series. Default 12.
#' @returns A data.table: the [reporting_completion_v1] columns plus a `scope` column
#'   ("year"/"month"), the year rows followed by the last-`n_months` month rows.
#'   Empty when no series has enough settled data.
#' @family reporting completion functions
#' @seealso Neither package vignette covers this function;
#'   \code{vignette("pipeline", package = "csalert")} runs
#'   \code{\link{reporting_completion_v1}}, which this one wraps.
#' @examples
#' w <- cstime::dates_by_isoyearweek$isoyearweek; i <- match("2023-01", w)
#' d <- data.table::data.table(
#'   isoyearweek_reference = w[i + rep(0:39, each = 3)],
#'   isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
#'   numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
#' tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
#' reporting_completion_trend_v1(tri, max_delay = 3, n_months = 6)
#' @export
reporting_completion_trend_v1 <- function(triangle, max_delay, n_months = 12L) {
  by_year <- reporting_completion_v1(triangle, max_delay, period = "year")
  by_month <- reporting_completion_v1(triangle, max_delay, period = "month")
  if (nrow(by_year)) {
    by_year[, scope := "year"]
  }
  if (nrow(by_month)) {
    id_cols <- attr(triangle, "id_cols")
    data.table::setorder(by_month, period)
    by_month <- by_month[, utils::tail(.SD, n_months), by = id_cols] # last N months per series
    by_month[, scope := "month"]
  }
  data.table::rbindlist(list(by_year, by_month), fill = TRUE)
}
