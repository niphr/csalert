# nowcast_delay_ecdf_v1: complete every incomplete reference week from a pooled
# DAILY DELAY ECDF.
#
# The reporting axis of csfmt_reporting_triangle_v3 is a calendar DATE, so a
# delay is a number of days. The engine asks one question per reference week:
# what share of a week's eventual total has arrived by delay day d? It answers
# with an empirical CDF pooled over the settled reference weeks inside
# `delay_window`, then divides:
#
#     p(d)           = cumsum(colSums(pool)) / sum(pool)
#     total_hat[ref] = observed_so_far[ref] / p(d_observed[ref])
#
# p(d) is non-decreasing by construction, and p(max_delay_days - 1) is 1.
#
# THE MODEL. This is the closed-form maximum likelihood estimator of
# n[ref, d] ~ Poisson(lambda[ref] * p[d]). The pooled ECDF increment is the MLE
# of p[d], and observed_so_far / P(d_observed) is the MLE of lambda[ref]. It is
# the same Poisson delay family the engine always had. The delay profile is now
# estimated SATURATED, one number per delay day, rather than through a
# regression, which is why the name no longer says quasipoisson.
#
# WHY THE REGRESSION WENT. The engine used to fit one quasipoisson parameter per
# delay column, `y ~ d1 + ... + dw`, on the settled weeks inside the window. With
# 5 WEEKLY delay columns that was 5 predictors on about 27 rows. With 35 DAILY
# columns it is 35 predictors on fewer rows than that. The fit is rank deficient,
# `anyNA(coef(fit))` is TRUE, and the old code returned NULL, which left that
# week at its observed value while still labelling it a nowcast. No error and no
# warning. The ECDF estimates each delay day from a count, so it does not
# degrade with the column count.
#
# THE INTERVAL IS EMPIRICAL. Each settled week in the pool is re-completed from
# its own first d + 1 delay days, and compared with its settled total. The 5%
# and 95% quantiles of that truth/estimate ratio, times the point estimate, are
# the interval. That single spread already carries the estimation error and the
# reporting noise together. An earlier build drew a normal for the parameter and
# a dispersion-matched negbin for the observation ON TOP of it, which counted
# the noise twice: measured coverage went to 0.97-1.00 against a nominal 0.90,
# where the empirical endpoints give 0.80-0.87.
#
# UNITS. `max_delay_days`, `age_days` and every ECDF index are DAYS.
# `delay_window` is WEEKS and keeps its name, so it is multiplied by 7 before it
# meets a day count. Two lines carry that conversion and neither errors when it
# is missing: the settled test and the training window test.
#
# NO WEEKDAY TERM. Every reference week starts on a Monday, so delay day d is
# always the same weekday. The ECDF absorbs the weekly reporting pattern.

# The share of a week's counts that has arrived by each delay day, pooled over
# the reference-week rows in `rows`. Returns NULL for an empty pool, because a
# share of nothing has no value. Dividing by the last cumulative entry, rather
# than by a separate sum(), makes the final entry exactly 1.
.delay_ecdf <- function(mat, rows) {
  cs <- cumsum(colSums(mat[rows, , drop = FALSE]))
  total <- cs[length(cs)]
  if (!is.finite(total) || total <= 0) {
    return(NULL)
  }
  return(cs / total)
}

# Which reference weeks train the ECDF, and what the ECDF is.
#
# `age_days` is the number of days from the reference week's Monday to the as-of
# date, so a week seen on the Wednesday of its own week has age 2. A week is
# settled once every delay day inside the horizon could have been reported,
# which is age_days >= max_delay_days - 1.
#
# BOTH comparisons below are in DAYS. The pre-Date engine compared a WEEK age
# against `max_delay`, and against `delay_window + max_delay`. Read in days
# under `max_delay_days = 35`, the first says "settled after 34 WEEKS" and the
# pool collapses to nothing. The second doubles the training window. Neither
# errors.
.delay_pool <- function(mat, refs, as_of, max_delay_days, delay_window) {
  age_days <- as.integer(as_of - isoyearweek_week_start(refs))
  known <- !is.na(age_days)
  settled <- known & age_days >= (max_delay_days - 1L)
  within <- rep(TRUE, length(age_days))
  if (!is.null(delay_window)) {
    within <- known & age_days < (delay_window * 7L + max_delay_days)
  }
  train <- which(settled & within)
  p <- NULL
  if (length(train) > 0L) {
    p <- .delay_ecdf(mat, train)
  }
  return(list(age_days = age_days, settled = settled, train = train, p = p))
}

# The completion ratio at one delay day, measured on the settled pool. Each
# settled week is re-completed from its own first `d + 1` delay days, then
# compared with its settled total. The 5% and 95% quantiles of this vector are
# the interval, so it must hold at least 3 weeks to be worth quoting.
.completion_ratio <- function(mat, train, pd, cols) {
  pool_truth <- rowSums(mat[train, , drop = FALSE])
  pool_pred <- rowSums(mat[train, cols, drop = FALSE]) / pd
  keep <- is.finite(pool_truth) & is.finite(pool_pred) & pool_pred > 0
  if (sum(keep) < 3L) {
    return(NULL)
  }
  return(pool_truth[keep] / pool_pred[keep])
}

# `n_sim` draws that carry the empirical interval, and nothing else. The draws
# are the pool's own ratio quantiles, scaled by the point estimate and floored
# at the observed count, so the 5% and 95% draw quantiles ARE
# `pred * quantile(ratio, c(0.05, 0.95))`. There is no parametric layer: no
# normal for the parameter and no negbin for the observation. The pool's spread
# already holds both.
#
# THE FLOOR CANNOT BIND, and it stays anyway. Each pool ratio is
# truth_s / (obs_s / p), so pred * ratio is obs * truth_s / obs_s, and obs_s is
# a partial sum of the non-negative counts truth_s totals. Every draw is
# therefore at or above the observed count already. Measured: removing the
# pmax() breaks no check. It is kept as a cheap guard for a future pool whose
# ratio is built some other way, and the invariant is checked directly on the
# replay rather than through this line.
#
# The order is then permuted. A sorted draw vector makes every reference week
# comonotone with every other, and the draw axis must stay exchangeable across
# weeks for the draw-parallel stages downstream. `sample.int(length(v))` rather
# than `sample(v)`, because `sample()` on a length-1 numeric permutes `1:v`.
.completion_draws <- function(pred, obs, rat, n_sim) {
  probs <- 0.5
  if (n_sim > 1L) {
    probs <- (seq_len(n_sim) - 1L) / (n_sim - 1L)
  }
  v <- pmax(pred * stats::quantile(rat, probs, names = FALSE), obs)
  return(v[sample.int(length(v))])
}

# One horizon: every incomplete reference week observed for exactly `d` days.
# Returns NULL when the horizon has no target week, or when the settled pool
# cannot price it.
.ecdf_horizon_draws <- function(d, mat, pool, n_sim) {
  tgt <- which(!pool$settled & pool$age_days == d)
  if (!length(tgt)) {
    return(NULL)
  }
  pd <- pool$p[d + 1L]
  if (!is.finite(pd) || pd <= 0) {
    return(NULL)
  }
  cols <- seq_len(d + 1L)
  rat <- .completion_ratio(mat, pool$train, pd, cols)
  if (is.null(rat)) {
    return(NULL)
  }
  obs_so_far <- rowSums(mat[tgt, cols, drop = FALSE])
  floor_at <- rowSums(mat[tgt, , drop = FALSE])
  out <- matrix(NA_real_, length(tgt), n_sim)
  for (ti in seq_along(tgt)) {
    out[ti, ] <- .completion_draws(
      obs_so_far[ti] / pd,
      floor_at[ti],
      rat,
      n_sim
    )
  }
  return(list(tgt = tgt, draws = out))
}

# Complete a reference x delay-day matrix into n_sim totals per reference week.
# Settled weeks keep their observed total, and so does any week the pool cannot
# price.
.ecdf_complete <- function(
  mat,
  refs,
  as_of,
  max_delay_days,
  n_sim,
  delay_window
) {
  obs_total <- rowSums(mat)
  draws <- matrix(obs_total, length(refs), n_sim)
  pool <- .delay_pool(mat, refs, as_of, max_delay_days, delay_window)
  if (length(pool$train) < 3L || is.null(pool$p)) {
    return(draws)
  }
  incomplete <- !pool$settled &
    !is.na(pool$age_days) &
    pool$age_days >= 0L &
    pool$age_days < (max_delay_days - 1L)
  for (d in sort(unique(pool$age_days[incomplete]))) {
    hz <- .ecdf_horizon_draws(d, mat, pool, n_sim)
    if (is.null(hz)) {
      next
    }
    draws[hz$tgt, ] <- hz$draws
  }
  return(draws)
}

#' Nowcast a reporting triangle into an ensemble (daily delay ECDF)
#'
#' Completes each incomplete reference week from a pooled daily delay ECDF. The
#' estimate is the count observed so far, divided by the share of a week that
#' normally arrives by that delay day.
#'
#' The engine pools the settled reference weeks inside `delay_window` and forms
#' `p(d)`, the cumulative share of a week's counts that arrives by delay day
#' `d`. `p(d)` is non-decreasing, and `p(max_delay_days - 1)` is 1. A reference
#' week observed for `d` days becomes `observed_so_far / p(d)`.
#'
#' That pair is the closed-form maximum likelihood estimator of
#' `n[ref, d] ~ Poisson(lambda[ref] * p[d])`. The delay profile is estimated
#' saturated, one number per delay day, rather than through a regression.
#'
#' The interval is empirical. Each settled week in the pool is re-completed from
#' its own first `d + 1` delay days, and compared with its settled total. The 5
#' to 95 band is the point estimate, times the 5% and 95% quantiles of that
#' `truth / estimate` ratio. Nothing parametric is added on top, because the
#' pool's own spread already carries the estimation error and the reporting
#' noise. A nowcast never falls below the observed count.
#'
#' There is no weekday term. Every reference week starts on a Monday, so delay
#' day `d` is always the same weekday, and the ECDF absorbs the weekly pattern.
#'
#' Whether the intervals are calibrated for YOUR series is an empirical
#' question. Measure it with [nowcast_evaluate_v1]. Shares the contract
#' `f(reporting_triangle, ...) -> csfmt_ensemble_v3`.
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param ... Passed to methods.
#' @family nowcast engines
#' @seealso \code{vignette("pipeline", package = "csalert")}, which runs this
#'   engine on a synthetic triangle and then scores it.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday, then
#' # right-truncated so the newest weeks are still incomplete
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
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' set.seed(2)
#' ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 21, n_sim = 200)
#' ens
#'
#' # settled weeks sit exactly on their observed total; the newest weeks are
#' # completed, and carry an interval
#' r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
#' tail(r[, .(
#'   isoyearweek, original,
#'   lo = numerator_nowcasted_q05x0,
#'   med = numerator_nowcasted_q50x0,
#'   hi = numerator_nowcasted_q95x0
#' )], 4)
#' @rdname nowcast_delay_ecdf_v1
#' @export
nowcast_delay_ecdf_v1 <- function(x, ...) UseMethod("nowcast_delay_ecdf_v1")

#' @method nowcast_delay_ecdf_v1 csfmt_reporting_triangle_v3
#' @rdname nowcast_delay_ecdf_v1
#' @param max_delay_days Delay horizon in DAYS: delay day 0 to
#'   `max_delay_days - 1`. `max_delay_days = 35` gives the 35 days that start on
#'   the reference week's Monday. Day `max_delay_days - 1` also holds every
#'   later delay.
#' @param n_sim Number of nowcast draws.
#' @param denominator_col Optional denominator column to nowcast alongside.
#' @param delay_window Train the ECDF on the settled weeks of roughly this many
#'   WEEKS, so it tracks a drifting reporting regime. Default 26. `NULL` uses
#'   every settled week. This argument is the one quantity here that is weeks
#'   and not days.
#' @returns A `csfmt_ensemble_v3` with one row per reference week, and an
#'   `n_sim`-column draw matrix of the nowcasted total per week. Settled weeks
#'   are degenerate at their observed total. Incomplete weeks carry the
#'   empirical completion interval measured on the settled pool. A second
#'   measure is added when `denominator_col` is given.
#' @export
nowcast_delay_ecdf_v1.csfmt_reporting_triangle_v3 <- function(
  x,
  max_delay_days,
  n_sim = 1000,
  denominator_col = NULL,
  delay_window = 26,
  ...
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  isoyearweek <- original <- time_series_id <- NULL
  id_cols <- attr(x, "id_cols")
  val_col <- attr(x, "value_col")
  as_of <- attr(x, "as_of")
  value_cols <- c(val_col, denominator_col)
  d_tri <- data.table::as.data.table(x)
  rts_num <- reporting_triangle_matrix(x, max_delay_days, value_col = val_col)
  series_ids <- names(rts_num)

  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(
      1L,
      length(refs)
    )]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay_days, value_col = vc)
    chunks <- lapply(series_ids, function(tsid) {
      return(.ecdf_complete(
        rts[[tsid]]$mat,
        rts[[tsid]]$reference,
        as_of,
        max_delay_days,
        n_sim,
        delay_window
      ))
    })
    draws[[csfmt_var(vc, role = "nowcasted")]] <- do.call(rbind, chunks)
    if (!identical(vc, val_col)) {
      obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
      data[, (csfmt_var(vc, role = "observed")) := obs]
    }
  }
  return(csfmt_ensemble_v3(
    data,
    id_cols = id_cols,
    time_col = "isoyearweek",
    draws = draws
  ))
}
