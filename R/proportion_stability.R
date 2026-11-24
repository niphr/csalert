# proportion_stability_v1: how far a proportion seen at delay day d is from its
# settled value, for each delay day of a reporting triangle.
#
# NorSySS reports proportions, numerator / denominator. Both arrive late, and a
# proportion can be stable long before its numerator is complete. So the count
# completion of reporting_completion_v1() alone overstates how unreliable the
# last weeks are. This function measures the proportion directly.
#
# The settled value is the cumulative count at delay day max_delay_days - 1,
# and `late` is NOT added. That is a fixed cut-off, so every settled week has
# the same follow-up. It is the convention of delay_distribution_v1(). It is
# not the convention of reporting_completion_v1(), which adds `late` to the
# last delay column.

# cumulative count by delay day, one row per reference week. M %*% U with an
# upper triangle of ones keeps the matrix shape for one row and for one column.
.ps_cumulate <- function(M) {
  n <- ncol(M)
  U <- matrix(0, n, n)
  U[upper.tri(U, diag = TRUE)] <- 1
  return(M %*% U)
}

# quantile of the errors at one delay day, NA when no week is kept
.ps_quantile <- function(x, prob) {
  if (length(x) == 0L) {
    return(NA_real_)
  }
  return(round(unname(stats::quantile(x, prob, type = 7)), 2))
}

# one output row for delay column d of the settled weeks: the pooled count
# completion and the quantiles of the proportion errors. p is the settled
# proportion of each week, and column `last` of cum_num is the settled count.
.ps_delay_row <- function(d, cum_num, cum_den, p, n_settled, last) {
  # weeks with no denominator yet at this delay day have no proportion
  e <- cum_den[, d] > 0
  p_d <- cum_num[e, d] / cum_den[, d][e]
  relerr <- 100 * abs(p_d / p[e] - 1)
  abserr <- 100 * abs(p_d - p[e])
  return(data.table::data.table(
    n_settled = n_settled,
    n_eval = sum(e),
    .delay_after_cols(d - 1L),
    pct_count = round(100 * sum(cum_num[, d]) / sum(cum_num[, last]), 1),
    prop_relerr_p50 = .ps_quantile(relerr, 0.5),
    prop_relerr_p90 = .ps_quantile(relerr, 0.9),
    prop_abserr_p50 = .ps_quantile(abserr, 0.5),
    prop_abserr_p90 = .ps_quantile(abserr, 0.9)
  ))
}

#' Measure how stable a proportion is at each delay day of a reporting triangle
#'
#' For each delay day, compares the proportion of numerator to denominator seen
#' at that day with its settled value. Use it next to [reporting_completion_v1()]
#' to see how many recent weeks of a proportion are reliable.
#'
#' Both counts come from [reporting_triangle_matrix()]. The settled value of a
#' week is its cumulative count at delay day `max_delay_days - 1`. A report at
#' delay `max_delay_days` or later is not in it. This is the convention of
#' [delay_distribution_v1()]. It is different from [reporting_completion_v1()],
#' which adds the reports past the horizon to the last delay day.
#'
#' A week is settled when its Monday is at least `max_delay_days - 1` days before
#' the as-of date, `attr(triangle, "as_of")`. A settled week is used only if its
#' settled numerator and its settled denominator are both above 0. A series with
#' fewer than 3 such weeks gets no rows, and no warning.
#'
#' At delay day `d`, a week has the proportion `p_d`, its cumulative numerator
#' divided by its cumulative denominator. Its settled proportion is `p`. A week
#' with a cumulative denominator of 0 at day `d` is not used at that day.
#' @param triangle The `csfmt_reporting_triangle_v3` to measure. The value column
#'   of the triangle is the numerator.
#' @param max_delay_days The delay horizon in days, delay day 0 to
#'   `max_delay_days - 1`.
#' @param denominator_col The name of the column of `triangle` that holds the
#'   denominator.
#' @param delay_window Use only the settled weeks of about this many recent weeks.
#'   It counts weeks, not days. `NULL` uses every settled week.
#' @returns A data.table with one row per series and delay day: the identity
#'   columns, `n_settled`, `n_eval`, `delay`, `day_after`, `week_after`,
#'   `pct_count`, `prop_relerr_p50`, `prop_relerr_p90`, `prop_abserr_p50` and
#'   `prop_abserr_p90`.
#' * `n_settled`: the settled weeks that the function uses.
#' * `n_eval`: the weeks of `n_settled` with a cumulative denominator above 0 at
#'   delay day `delay`.
#' * `delay`: the delay day, an integer from 0 to `max_delay_days - 1`.
#' * `day_after`: the integer `delay - 6`. Day 1 is the Monday after the
#'   reference week.
#' * `week_after`: the integer `delay / 7` where `delay` is a multiple of 7,
#'   and `NA` on every other day.
#' * `pct_count`: the pooled cumulative numerator at `delay`, in percent of the
#'   pooled settled numerator, over the `n_settled` weeks. It has 1 decimal.
#' * `prop_relerr_p50`, `prop_relerr_p90`: the median and the 90th percentile of
#'   `100 * abs(p_d / p - 1)`, in percent of the settled proportion.
#' * `prop_abserr_p50`, `prop_abserr_p90`: the median and the 90th percentile of
#'   `100 * abs(p_d - p)`, in percentage points.
#'
#' The four error columns use `stats::quantile(type = 7)` over the `n_eval`
#' weeks, and have 2 decimals. They are `NA` where `n_eval` is 0. The result is
#' an empty data.table when no series has 3 weeks to use.
#' @inheritSection delay_distribution_v1 Delay convention
#' @family reporting completion functions
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:19, each = 2)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(1, 8), 20),
#'   numerator = rep(c(3, 1), 20),
#'   denominator = rep(c(10, 10), 20),
#'   indicator = "x", location = "nation", age = "total", sex = "total"
#' )
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator", "location", "age", "sex")
#' )
#'
#' # The proportion is 0.3 on day 1 and 0.2 when it settles on day 8, so the
#' # relative error is 50 percent from day 1 to day 7.
#' ps <- proportion_stability_v1(tri, max_delay_days = 9, "denominator")
#' ps[, .(delay, n_eval, pct_count, prop_relerr_p50, prop_abserr_p50)]
#' @export
proportion_stability_v1 <- function(
  triangle,
  max_delay_days,
  denominator_col,
  delay_window = NULL
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_id <- NULL
  stopifnot(
    inherits(triangle, "csfmt_reporting_triangle_v3"),
    is.character(denominator_col),
    length(denominator_col) == 1L,
    denominator_col %in% names(triangle)
  )
  rts_num <- reporting_triangle_matrix(
    triangle,
    max_delay_days,
    value_col = attr(triangle, "value_col")
  )
  rts_den <- reporting_triangle_matrix(
    triangle,
    max_delay_days,
    value_col = denominator_col
  )
  as_of <- attr(triangle, "as_of")
  id_cols <- attr(triangle, "id_cols")
  d_tri <- data.table::as.data.table(triangle)
  last <- max_delay_days

  out <- list()
  for (tsid in names(rts_num)) {
    num <- rts_num[[tsid]]
    den <- rts_den[[tsid]]
    if (
      is.null(den) ||
        !identical(num$reference, den$reference) ||
        !identical(dim(num$mat), dim(den$mat))
    ) {
      stop(
        "the numerator and denominator matrices of series ",
        tsid,
        " differ in `reference` or `dim`",
        call. = FALSE
      )
    }
    week_start <- isoyearweek_week_start(num$reference)
    # Age in DAYS, from the reference week's Monday to the as-of date, and the
    # same settled rule and delay_window as reporting_completion_v1().
    age <- as.integer(as_of - week_start)
    keep <- age >= (max_delay_days - 1L)
    if (!is.null(delay_window)) {
      # delay_window is in WEEKS, so convert it before comparing against days
      keep <- keep & age < (delay_window * 7L + max_delay_days)
    }
    if (!any(keep)) {
      next
    }
    # `late` is not added: the settled value is the count at the last delay day
    cum_num <- .ps_cumulate(num$mat[keep, , drop = FALSE])
    cum_den <- .ps_cumulate(den$mat[keep, , drop = FALSE])
    ok <- cum_num[, last] > 0 & cum_den[, last] > 0
    if (sum(ok) < 3L) {
      next
    }
    cum_num <- cum_num[ok, , drop = FALSE]
    cum_den <- cum_den[ok, , drop = FALSE]
    p <- cum_num[, last] / cum_den[, last]
    ids <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[1]

    rows <- lapply(
      seq_len(max_delay_days),
      .ps_delay_row,
      cum_num = cum_num,
      cum_den = cum_den,
      p = p,
      n_settled = sum(ok),
      last = last
    )
    out[[tsid]] <- data.table::data.table(ids, data.table::rbindlist(rows))
  }
  return(data.table::rbindlist(out, fill = TRUE))
}
