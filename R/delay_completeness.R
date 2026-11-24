# delay_distribution_v1() and outage_weeks_v1(): the delay distribution of one
# series of a reporting triangle, corrected for right truncation, and its old
# weeks with a reporting outage.
#
# Ported from luftveisovervaking_trend, R_examination_of_trend/
# nowcast_negbin_gam.R: .delay_probs_truncated() and .outage_weeks(). The two
# helpers below keep their arithmetic, and test-delay_completeness.R checks
# that they give the same values. The one change: the delay helper returns 1
# for one delay column before it computes the cumulative sums. That
# nowcast also chooses a window of weeks before it calls them, and leaves the
# outage weeks out of the delay distribution. Both functions here leave that
# choice to the caller, who filters the triangle.

# The one series of x as rows of reporting_triangle_matrix(), with n_seen, the
# number of delay days each row has seen at the as-of date. Only the rows whose
# reference Monday is on or before the as-of date.
.dc_rows <- function(x, max_delay_days, fn) {
  stopifnot(inherits(x, "csfmt_reporting_triangle_v3"))
  n_series <- data.table::uniqueN(x[["time_series_id"]])
  if (n_series != 1L) {
    stop(
      fn,
      "() needs a triangle with one series, and this one has ",
      n_series,
      ". Filter it on its id columns: ",
      paste(attr(x, "id_cols"), collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  m <- reporting_triangle_matrix(x, max_delay_days)[[1]]
  age_days <- as.integer(attr(x, "as_of") - isoyearweek_week_start(m$reference))
  k <- which(age_days >= 0L)
  return(list(
    reference = as.character(m$reference[k]),
    mat = m$mat[k, , drop = FALSE],
    n_seen = pmin(age_days[k] + 1L, max_delay_days)
  ))
}

# The delay column and the two columns of the reader convention, one row per
# delay day. delay_distribution_v1() and proportion_stability_v1() both call
# it. Delay day 0 is the reference Monday, so day_after 1 and week_after 1 are
# both delay 7, the Monday after the week. week_after is NA on the other six
# weekdays.
.delay_after_cols <- function(delay) {
  week_after <- delay %/% 7L
  week_after[delay %% 7L != 0L] <- NA_integer_
  return(data.table::data.table(
    delay = delay,
    day_after = delay - 6L,
    week_after = week_after
  ))
}

# .delay_probs_truncated() of luftveis. Row i of rt has seen its first
# n_seen[i] delay days. The product-limit estimate runs backwards from the last
# delay, where the cdf F = 1:
#   F(d - 1) / F(d) = sum_i C_i(d - 1) / sum_i C_i(d), over the rows with delay d seen,
# where C_i(d) is the count of row i reported by delay d.
.dc_delay_probs <- function(rt, n_seen) {
  n_d <- ncol(rt)
  if (n_d == 1L) {
    return(1)
  }
  cum <- t(apply(rt, 1, cumsum))
  cdf <- numeric(n_d)
  cdf[n_d] <- 1
  for (d in seq(n_d, 2L)) {
    w <- n_seen >= d
    den <- sum(cum[w, d])
    cdf[d - 1L] <- if (den > 0) cdf[d] * sum(cum[w, d - 1L]) / den else cdf[d]
  }
  # a flat stretch of the cdf can differ by rounding (-1e-14)
  return(pmax(diff(c(0, cdf)), 0))
}

# .outage_weeks() of luftveis: the row indices of rt that are reporting
# outages.
.dc_outage_rows <- function(rt, n_seen, early_days, min_weeks_back, frac) {
  n_t <- nrow(rt)
  old <- which(n_t - seq_len(n_t) >= min_weeks_back & n_seen > early_days)
  old <- old[rowSums(rt[old, , drop = FALSE]) > 0]
  if (length(old) < 4L) {
    return(integer())
  }
  share <- rowSums(rt[old, seq_len(early_days + 1L), drop = FALSE]) /
    rowSums(rt[old, , drop = FALSE])
  return(old[share < frac * stats::median(share)])
}

#' Estimate the delay distribution of a reporting triangle
#'
#' Estimates the probability that a case is reported on each delay day, from 0
#' to `max_delay_days - 1`. The estimate uses every reference week, and corrects
#' for the weeks that are not fully reported yet.
#'
#' The function uses the rows of [reporting_triangle_matrix()] whose reference
#' Monday is on or before the as-of date, `attr(x, "as_of")`. `age_days` is the
#' number of days from that Monday to the as-of date. A row has seen delay days
#' 0 to `n_seen - 1`, with `n_seen = pmin(age_days + 1, max_delay_days)`.
#'
#' The product-limit estimate starts at the last delay day, where the cumulative
#' distribution `F` is 1. Then `F(d - 1) / F(d)` is the count reported by delay
#' `d - 1`, divided by the count reported by delay `d`. Both sums use only the
#' rows that have seen delay `d`. Where the count by delay `d` is 0,
#' `F(d - 1) = F(d)`. A report at delay `max_delay_days` or later is not in the
#' estimate, so `p` is conditional on a report within the horizon.
#'
#' The function does not choose a window of weeks. It also keeps the weeks with
#' a reporting outage, which [outage_weeks_v1()] finds. To leave weeks out,
#' filter `x` before the call. A triangle filtered with `[` keeps its as-of date.
#' @param x A `csfmt_reporting_triangle_v3` with one series. With more than one
#'   `time_series_id`, the function stops with an error that names the id
#'   columns of `x`.
#' @param max_delay_days The delay horizon in days, delay day 0 to
#'   `max_delay_days - 1`.
#' @returns A data.table with one row per delay day and four columns:
#' * `delay`: the delay day, an integer from 0 to `max_delay_days - 1`.
#' * `day_after`: the integer `delay - 6`. Day 1 is the Monday after the
#'   reference week.
#' * `week_after`: the integer `delay / 7` where `delay` is a multiple of 7,
#'   and `NA` on every other day.
#' * `p`: the probability of a report on delay day `delay`. With
#'   `max_delay_days = 1`, `p` is 1.
#' @section Delay convention:
#' Delay day 0 is the Monday of the reference ISO week, and delay `d` is `d`
#' days after it. NorSySS readers count from the end of the week instead.
#' The columns `day_after` and `week_after` give their count.
#'
#' * `day_after` k is the k-th day after the week, so day 1 is the Monday after
#'   the week. The values from -6 to 0 are days inside the week: -6 is its
#'   Monday, and 0 is the Sunday that ends it.
#' * `week_after` k is the Monday k weeks after the week, so week 1 is day 1
#'   and week 2 is day 8.
#'
#' For example, week 2026-46 starts on Monday 2026-11-09. Delay 7 is Monday
#' 2026-11-16, which is day 1 and week 1. Delay 14 is day 8 and week 2.
#' A horizon of 63 days, 9 weeks, puts week 8 at delay 56, inside the horizon.
#' @seealso [reporting_completion_v1()], which pools only the weeks old enough to
#'   be fully reported.
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
#' # this series reports on days 3, 10 and 17 after the reference Monday
#' dd <- delay_distribution_v1(tri, max_delay_days = 21)
#' dd[p > 0]
#'
#' # the last 20 reference weeks only
#' delay_distribution_v1(tri[isoyearweek_reference >= "2023-21"], 21)[p > 0]
#' @export
delay_distribution_v1 <- function(x, max_delay_days) {
  r <- .dc_rows(x, max_delay_days, "delay_distribution_v1")
  return(data.table::data.table(
    .delay_after_cols(seq_len(max_delay_days) - 1L),
    p = .dc_delay_probs(r$mat, r$n_seen)
  ))
}

#' Find the old weeks of a reporting triangle with a reporting outage
#'
#' Finds the old reference weeks whose early reports are a small share of their
#' count. In [delay_distribution_v1()], such a week makes reporting look slower
#' than it is.
#'
#' The rows and `n_seen` are those of [delay_distribution_v1()]. A row is a
#' candidate when all three hold:
#' * it is at least `min_weeks_back` weeks older than the newest row,
#' * its `n_seen` is more than `early_days`, and
#' * its count on delay days 0 to `max_delay_days - 1` is more than 0.
#'
#' With fewer than 4 candidates, the function flags no week. Otherwise, the share
#' of a candidate is its early count divided by its count on delay days 0 to
#' `max_delay_days - 1`. The early count is the count on delay days 0 to
#' `early_days`. The function flags a candidate when its share is below `frac`
#' times the median share of the candidates.
#'
#' The function does not choose a window of weeks. To look in a window, filter
#' `x` before the call. A triangle filtered with `[` keeps its as-of date.
#' @inheritParams delay_distribution_v1
#' @param early_days The last delay day of the early reports. With the default
#'   9, the early reports are those on delay days 0 to 9.
#' @param min_weeks_back A candidate is at least this many weeks older than the
#'   newest row.
#' @param frac A candidate is flagged when its share is below `frac` times the
#'   median share.
#' @returns A data.table with one character column, `isoyearweek_reference`: the
#'   flagged reference weeks, oldest first. It has zero rows when the function
#'   flags no week.
#' @seealso [delay_distribution_v1()], to estimate the delay distribution
#'   without the flagged weeks.
#' @examples
#' monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(monday, "%G-%V"),
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' # week 2023-20 has an outage: most of its cases arrive on day 17
#' d[isoyearweek_reference == "2023-20", numerator := c(2L, 3L, 45L)]
#' d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' out <- outage_weeks_v1(tri, max_delay_days = 21)
#' out
#'
#' # the delay distribution without the outage week
#' tri_ok <- tri[!isoyearweek_reference %in% out$isoyearweek_reference]
#' delay_distribution_v1(tri_ok, 21)[p > 0]
#' @export
outage_weeks_v1 <- function(
  x,
  max_delay_days,
  early_days = 9L,
  min_weeks_back = 5L,
  frac = 0.5
) {
  r <- .dc_rows(x, max_delay_days, "outage_weeks_v1")
  rows <- .dc_outage_rows(r$mat, r$n_seen, early_days, min_weeks_back, frac)
  return(data.table::data.table(isoyearweek_reference = r$reference[rows]))
}
