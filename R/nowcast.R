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
  ref_date <- cstime::isoyearweek_to_last_date(ll[[ref_col]])
  rep_date <- cstime::isoyearweek_to_last_date(ll[[rep_col]])
  as_of_date <- cstime::isoyearweek_to_last_date(as_of)

  delay     <- pmax(0, round(as.numeric(rep_date - ref_date) / 7))
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

#' Nowcast a reporting triangle into an ensemble
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param ... Passed to methods.
#' @rdname nowcast
#' @export
nowcast <- function(x, ...) {
  UseMethod("nowcast")
}

#' @method nowcast csfmt_reporting_triangle_v3
#' @rdname nowcast
#' @param max_delay Delay horizon in weeks.
#' @param n_sim Number of nowcast draws.
#' @export
nowcast.csfmt_reporting_triangle_v3 <- function(x, max_delay, n_sim = 1000, ...) {
  if (!requireNamespace("flexsurv", quietly = TRUE))
    stop("nowcast requires the 'flexsurv' package")
  id_cols <- attr(x, "id_cols")
  ref_col <- attr(x, "reference_col"); rep_col <- attr(x, "reporting_col")
  val_col <- attr(x, "value_col");     as_of   <- attr(x, "as_of")

  rts <- reporting_triangle_matrix(x, max_delay)
  d_tri <- data.table::as.data.table(x)

  data_rows <- list(); draw_rows <- list()
  for (tsid in names(rts)) {
    refs <- rts[[tsid]]$reference
    mat  <- rts[[tsid]]$mat
    cum_by_delay <- nowcast_delay_cumdist(d_tri[time_series_id == tsid],
                                          ref_col, rep_col, val_col, as_of, max_delay)
    draws <- nowcast_complete(mat, cum_by_delay, n_sim)

    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(1L, length(refs))]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(mat)]
    data_rows[[tsid]] <- idvals
    draw_rows[[tsid]] <- draws
  }

  data <- data.table::rbindlist(data_rows)
  draws_mat <- do.call(rbind, draw_rows)
  measure <- csfmt_var(val_col, role = "nowcasted")
  csfmt_ensemble_v3(data, id_cols = id_cols, time_col = "isoyearweek",
                    draws = stats::setNames(list(draws_mat), measure))
}
