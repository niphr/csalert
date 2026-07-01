# nowcast: csfmt_reporting_triangle_v3 -> csfmt_ensemble_v3.
#
# Ports the luftveis nowcast_simple, but on the data.table reshape instead of
# epinowcast: estimate the reporting-delay distribution by truncated survival
# (flexsurv::survrtrunc), then for each not-yet-fully-reported reference week
# complete the count with a negative-binomial draw. n_sim draws -> the nowcast
# ensemble. The completed reference-week totals become the ensemble's draw matrix.

# P(reported by delay d), d = 0..max_delay-1, from this series' line list.
nowcast_delay_cumdist <- function(ds, ref_col, rep_col, val_col, as_of, max_delay) {
  ds <- ds[get(val_col) > 0]
  ll <- ds[rep(seq_len(.N), ds[[val_col]])]
  if (nrow(ll) == 0) return(rep(1, max_delay))    # nothing observed -> no completion
  ref_date <- cstime::isoyearweek_to_last_date(ll[[ref_col]])
  rep_date <- cstime::isoyearweek_to_last_date(ll[[rep_col]])
  as_of_date <- cstime::isoyearweek_to_last_date(as_of)

  delay     <- pmax(0, round(as.numeric(rep_date - ref_date) / 7))
  if (max(delay) == 0) return(rep(1, max_delay))  # passthrough: all reported at delay 0
  max_diff  <- round(as.numeric(as_of_date - ref_date) / 7)
  init_time <- round(as.numeric(rep_date - min(ref_date)) / 7)

  s <- flexsurv::survrtrunc(t = delay, rtrunc = max_diff, tmax = max(init_time),
                            data = data.frame(X = init_time, T = delay, rtrunc = max_diff))
  cd <- 1 - s$surv                                    # cumulative reported by s$time
  # map to integer delays 0..max_delay-1; cum_by_delay[m] = P(reported by delay m-1)
  stats::approx(x = s$time, y = cd, xout = 0:(max_delay - 1), rule = 2)$y
}

# Complete a reference x delay count matrix into n_sim nowcasted totals per
# reference week. Returns [n_ref x n_sim].
nowcast_complete <- function(mat, cum_by_delay, n_sim) {
  nref <- nrow(mat); ndelay <- ncol(mat)
  obs_total <- rowSums(mat)
  draws <- matrix(0, nref, n_sim)
  for (i in seq_len(n_sim)) {
    nowcasted <- obs_total
    for (j in seq_len(nref)) {
      for (k in seq_len(ndelay)) {
        if (k + j - 1 > nref) {                       # delay k not yet observable for row j
          obs <- obs_total[j]
          if (obs > 0) {
            seen_p <- cum_by_delay[k - 1]
            seen_p <- min(max(seen_p, 1e-6), 1 - 1e-9)
            nowcasted[j] <- obs + stats::rnbinom(1, size = obs, prob = seen_p)
          }
          break
        }
      }
    }
    draws[, i] <- nowcasted
  }
  draws
}

#' Build an ensemble from a reporting triangle WITHOUT nowcasting (passthrough)
#'
#' The passthrough counterpart to [nowcast_simple]: collapse the triangle to the
#' observed (reported-so-far) totals per reference week and wrap them as a
#' degenerate single-draw ensemble. An indicator that should NOT be
#' nowcast-completed (because reporting is effectively complete, or the analyst
#' has chosen not to model the delay) then flows through the SAME
#' rate/trend/MEM/collapse pipeline with its observed values unchanged. It emits
#' the same `<measure>_nowcasted` columns as [nowcast_simple] -- here equal to the
#' observed value -- so all downstream code is identical; the single draw makes
#' every collapsed quantile equal the observed point.
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param max_delay Delay horizon (defines the contiguous reference grid).
#' @param denominator_col Optional denominator column, carried through the same
#'   way (its observed total is also surfaced as `<denom>_observed`).
#' @returns A `csfmt_ensemble_v3` with single-column draw matrices.
#' @export
nowcast_passthrough_to_ensemble <- function(x, max_delay, denominator_col = NULL) {
  stopifnot(inherits(x, "csfmt_reporting_triangle_v3"))
  id_cols <- attr(x, "id_cols")
  val_col <- attr(x, "value_col")
  value_cols <- c(val_col, denominator_col)
  d_tri <- data.table::as.data.table(x)

  rts_num <- reporting_triangle_matrix(x, max_delay, value_col = val_col)
  series_ids <- names(rts_num)

  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(1L, length(refs))]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay, value_col = vc)
    obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
    draws[[csfmt_var(vc, role = "nowcasted")]] <- matrix(obs, ncol = 1)
    if (!identical(vc, val_col)) data[, (csfmt_var(vc, role = "observed")) := obs]
  }

  csfmt_ensemble_v3(data, id_cols = id_cols, time_col = "isoyearweek", draws = draws)
}

#' Nowcast a reporting triangle into an ensemble (simple flexsurv+negbin engine)
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param ... Passed to methods.
#' @rdname nowcast_simple
#' @export
nowcast_simple <- function(x, ...) {
  UseMethod("nowcast_simple")
}

#' @method nowcast_simple csfmt_reporting_triangle_v3
#' @rdname nowcast_simple
#' @param max_delay Delay horizon in weeks.
#' @param n_sim Number of nowcast draws.
#' @param denominator_col Optional denominator column in the triangle to nowcast
#'   alongside the numerator (index-aligned, for rates). The completed draw matrix
#'   is added as a second measure.
#' @export
nowcast_simple.csfmt_reporting_triangle_v3 <- function(x, max_delay, n_sim = 1000,
                                                denominator_col = NULL, ...) {
  if (!requireNamespace("flexsurv", quietly = TRUE))
    stop("nowcast_simple requires the 'flexsurv' package")
  id_cols <- attr(x, "id_cols")
  ref_col <- attr(x, "reference_col"); rep_col <- attr(x, "reporting_col")
  val_col <- attr(x, "value_col");     as_of   <- attr(x, "as_of")
  value_cols <- c(val_col, denominator_col)

  d_tri <- data.table::as.data.table(x)
  rts_num <- reporting_triangle_matrix(x, max_delay, value_col = val_col)
  series_ids <- names(rts_num)

  # $data (identity + reference weeks + observed numerator), built once. The
  # reference grid is identical across value columns (num/denom share rows).
  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(1L, length(refs))]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  # complete each measure (numerator + optional denominator), per series
  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay, value_col = vc)
    chunks <- lapply(series_ids, function(tsid) {
      cum_by_delay <- nowcast_delay_cumdist(d_tri[time_series_id == tsid],
                                            ref_col, rep_col, vc, as_of, max_delay)
      nowcast_complete(rts[[tsid]]$mat, cum_by_delay, n_sim)
    })
    draws[[csfmt_var(vc, role = "nowcasted")]] <- do.call(rbind, chunks)
    # Observed (reported-so-far) total for a secondary measure, e.g. the
    # denominator. The numerator's observed total is already `original`; this
    # makes the denominator's observed total available too (rows align: num/denom
    # share the reference grid), so downstream rate plots can use observed
    # counts instead of the nowcast median.
    if (!identical(vc, val_col)) {
      obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
      data[, (csfmt_var(vc, role = "observed")) := obs]
    }
  }

  csfmt_ensemble_v3(data, id_cols = id_cols, time_col = "isoyearweek", draws = draws)
}
