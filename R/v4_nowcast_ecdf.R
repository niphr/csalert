# nowcast_ecdf_v4: a copy of nowcast_delay_ecdf_v1 on the v4 formats. It
# completes every incomplete reference week from the completion ratios of the
# settled weeks in a window, at the same delay day. `max_delay_days`, the age
# of a week and every ECDF index are DAYS. `delay_window` is WEEKS. With the
# same triangle and seed, its draws are identical() to those of
# nowcast_delay_ecdf_v1.

# The share of the counts that has arrived by each delay day, pooled over the
# rows in `rows`. NULL for an empty pool.
.v4_delay_ecdf <- function(mat, rows) {
  cs <- cumsum(colSums(mat[rows, , drop = FALSE]))
  total <- cs[length(cs)]
  if (!is.finite(total) || total <= 0) {
    return(NULL)
  }
  return(cs / total)
}

# The weeks that train the ECDF, and the ECDF. A week is settled when its age
# in days is at least max_delay_days - 1. A week in the window is younger than
# delay_window * 7 + max_delay_days days. A week with no count inside the
# horizon and a count past it holds no delay information, and stays out.
.v4_delay_pool <- function(
  mat,
  refs,
  as_of,
  max_delay_days,
  delay_window,
  late = numeric(nrow(mat))
) {
  age_days <- as.integer(as_of - .v4_isoyearweek_week_start(refs))
  known <- !is.na(age_days)
  settled <- known & age_days >= (max_delay_days - 1L)
  within <- rep(TRUE, length(age_days))
  if (!is.null(delay_window)) {
    within <- known & age_days < (delay_window * 7L + max_delay_days)
  }
  no_info <- rowSums(mat) == 0 & late > 0
  train <- which(settled & within & !no_info)
  p <- NULL
  if (length(train) > 0L) {
    p <- .v4_delay_ecdf(mat, train)
  }
  return(list(age_days = age_days, settled = settled, train = train, p = p))
}

# The completion ratio of each settled pool week at one delay day: its total
# over its estimate from the first `d + 1` delay days. NULL with fewer than 3
# usable weeks.
.v4_completion_ratio <- function(mat, train, pd, cols) {
  pool_truth <- rowSums(mat[train, , drop = FALSE])
  pool_pred <- rowSums(mat[train, cols, drop = FALSE]) / pd
  keep <- is.finite(pool_truth) & is.finite(pool_pred) & pool_pred > 0
  if (sum(keep) < 3L) {
    return(NULL)
  }
  return(pool_truth[keep] / pool_pred[keep])
}

# `n_sim` draws: the ratio quantiles at evenly spaced probabilities, times the
# point estimate, floored at the observed count, in random order.
# sample.int(length(v)) and not sample(v), because sample() on a length-1
# numeric permutes 1:v.
.v4_completion_draws <- function(pred, obs, rat, n_sim) {
  probs <- 0.5
  if (n_sim > 1L) {
    probs <- (seq_len(n_sim) - 1L) / (n_sim - 1L)
  }
  v <- pmax(pred * stats::quantile(rat, probs, names = FALSE), obs)
  return(v[sample.int(length(v))])
}

# The draws of every incomplete week of age `d` days. NULL when no week has
# that age, or when the pool cannot price that delay day.
.v4_ecdf_horizon_draws <- function(d, mat, pool, n_sim) {
  tgt <- which(!pool$settled & pool$age_days == d)
  if (!length(tgt)) {
    return(NULL)
  }
  pd <- pool$p[d + 1L]
  if (!is.finite(pd) || pd <= 0) {
    return(NULL)
  }
  cols <- seq_len(d + 1L)
  rat <- .v4_completion_ratio(mat, pool$train, pd, cols)
  if (is.null(rat)) {
    return(NULL)
  }
  obs_so_far <- rowSums(mat[tgt, cols, drop = FALSE])
  floor_at <- rowSums(mat[tgt, , drop = FALSE])
  out <- matrix(NA_real_, length(tgt), n_sim)
  for (ti in seq_along(tgt)) {
    out[ti, ] <- .v4_completion_draws(
      obs_so_far[ti] / pd,
      floor_at[ti],
      rat,
      n_sim
    )
  }
  return(list(tgt = tgt, draws = out))
}

# The weeks to complete: reached by the as-of date and not yet settled.
.v4_incomplete_weeks <- function(pool, max_delay_days) {
  return(
    !pool$settled &
      !is.na(pool$age_days) &
      pool$age_days >= 0L &
      pool$age_days < (max_delay_days - 1L)
  )
}

# Complete one series into `n_sim` totals per reference week. A settled week,
# and a week the pool cannot price, keeps its observed total rowSums(mat) +
# late in every draw.
.v4_ecdf_complete <- function(
  mat,
  refs,
  as_of,
  max_delay_days,
  n_sim,
  delay_window,
  late
) {
  draws <- matrix(rowSums(mat) + late, length(refs), n_sim)
  pool <- .v4_delay_pool(mat, refs, as_of, max_delay_days, delay_window, late)
  if (length(pool$train) < 3L || is.null(pool$p)) {
    return(draws)
  }
  incomplete <- .v4_incomplete_weeks(pool, max_delay_days)
  for (d in sort(unique(pool$age_days[incomplete]))) {
    hz <- .v4_ecdf_horizon_draws(d, mat, pool, n_sim)
    if (is.null(hz)) {
      next
    }
    draws[hz$tgt, ] <- hz$draws + late[hz$tgt]
  }
  return(draws)
}

#' Nowcast a reporting triangle from the delay pattern of settled weeks
#'
#' Completes each incomplete reference week from a pool of settled reference
#' weeks. Each draw is the count observed so far, times a quantile of the
#' completion ratios that the pool shows at the same delay day.
#'
#' The method is that of [nowcast_delay_ecdf_v1()]. With the same triangle and
#' the same seed, the draws are identical. The draw matrix has the name of
#' `value_col`, with no suffix. The function sets the seed itself and then
#' restores the random-number state of the caller.
#' @param x The `csfmt_reporting_triangle_v4` to nowcast.
#' @param max_delay_days The delay horizon in days, delay day 0 to
#'   `max_delay_days - 1`. The nowcast estimates the count reported within it.
#' @param seed The seed of the draws, one whole number.
#' @param n_sim The number of draws.
#' @param denominator_col A denominator column to nowcast on the same draws. Its
#'   observed total goes to `$data` as `<denominator_col>_observed`.
#' @param delay_window The span, in weeks, of the settled weeks in the pool.
#'   `NULL` uses every settled week.
#' @returns A `csfmt_ensemble_v4` with one row per reference week. `$draws`
#'   holds one matrix with `n_sim` columns per measure, named by the measure.
#'   `$data` holds `original`, the observed total, which includes every report
#'   at delay `max_delay_days` or later.
#' @family v4 functions
#' @examples
#' cal <- cstime::dates_by_isoyearweek
#' i <- match("2023-01", cal$isoyearweek)
#' set.seed(1)
#' monday <- as.Date(cal$mon[i + rep(0:39, each = 3)])
#' d <- data.table::data.table(
#'   isoyearweek_reference = cal$isoyearweek[i + rep(0:39, each = 3)],
#'   reporting_date = monday + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= as.Date(cal$mon[i + 39]) + 6]
#' tri <- csfmt_reporting_triangle_v4(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#' ens <- nowcast_ecdf_v4(tri, max_delay_days = 21, seed = 4, n_sim = 200)
#' ens
#' @export
nowcast_ecdf_v4 <- function(
  x,
  max_delay_days,
  seed,
  n_sim = 1000,
  denominator_col = NULL,
  delay_window = 26
) {
  stopifnot(inherits(x, "csfmt_reporting_triangle_v4"))
  val_col <- attr(x, "value_col")
  as_of <- attr(x, "as_of")
  value_cols <- c(val_col, denominator_col)
  .v4_check_measure_names(value_cols)
  rts_num <- .v4_reporting_triangle_matrix(x, max_delay_days, val_col)
  series_ids <- names(rts_num)
  data <- .v4_triangle_frame(x, rts_num)

  draws <- .v4_with_seed(seed, {
    out <- list()
    for (vc in value_cols) {
      rts <- .v4_reporting_triangle_matrix(x, max_delay_days, vc)
      chunks <- lapply(series_ids, function(tsid) {
        return(.v4_ecdf_complete(
          rts[[tsid]]$mat,
          rts[[tsid]]$reference,
          as_of,
          max_delay_days,
          n_sim,
          delay_window,
          rts[[tsid]]$late
        ))
      })
      out[[vc]] <- do.call(rbind, chunks)
      if (!identical(vc, val_col)) {
        data[,
          (.v4_var(vc, role = "observed")) := .v4_observed_total(
            rts,
            series_ids
          )
        ]
      }
    }
    out
  })
  return(csfmt_ensemble_v4(
    data,
    id_cols = attr(x, "id_cols"),
    time_col = "isoyearweek",
    draws = draws
  ))
}
