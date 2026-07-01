# reporting_completion: the empirical reporting-delay summary of a triangle --
# "how long until a reference week's cases are (nearly) all in".
#
# From the SETTLED weeks (old enough to know their final total -- else the
# right-truncation makes recent weeks look more complete than they are), pool the
# cumulative fraction reported by each delay, then read off: the mean delay, the
# weeks-observed to reach 25/50/75/90/95% (interpolated, 1-based so "1" = the
# current week with only its delay-0 reports), and how complete a week actually is
# by max_delay (< 1 means reporting still dribbles in past the horizon -- itself a
# signal). delay_window restricts to recent settled weeks so a drifting reporting
# speed shows the CURRENT curve, not a long-run average.

#' Empirical reporting-completion summary from a reporting triangle
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay Delay horizon in weeks.
#' @param delay_window Optional: use only settled weeks within roughly this many
#'   weeks (drift-aware). `NULL` uses all settled weeks.
#' @param probs Completion levels to report the weeks-observed for.
#' @returns One row per series: identity columns + `n_settled`, `mean_delay`,
#'   `complete_by_md` (fraction in by `max_delay`), and `w25`..`w95` (weeks
#'   observed to reach each level; NA if not reached within `max_delay`).
#' @export
reporting_completion <- function(triangle, max_delay, delay_window = NULL,
                                 probs = c(.25, .5, .75, .9, .95)) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  rts <- reporting_triangle_matrix(triangle, max_delay)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  as_of_i <- match(attr(triangle, "as_of"), weeks)
  id_cols <- attr(triangle, "id_cols")
  d_tri <- data.table::as.data.table(triangle)

  out <- list()
  for (tsid in names(rts)) {
    refs <- rts[[tsid]]$reference; mat <- rts[[tsid]]$mat
    age <- as_of_i - match(refs, weeks)
    keep <- age >= (max_delay - 1L)
    if (!is.null(delay_window)) keep <- keep & age < (delay_window + max_delay)
    M <- mat[keep, , drop = FALSE]
    tot <- rowSums(M); ok <- tot > 0
    if (sum(ok) < 3L) next
    cum  <- t(apply(M[ok, , drop = FALSE], 1, cumsum))
    frac <- colSums(cum) / sum(tot[ok])                 # pooled cumulative fraction by delay

    wto <- vapply(probs, function(p) {
      d <- which(frac >= p)[1]                          # first delay (1-based col) reaching p
      if (is.na(d)) return(NA_real_)
      if (d == 1L) return(1)                            # in by delay 0 -> 1 week observed
      f0 <- frac[d - 1L]; f1 <- frac[d]
      (d - 1L) + (p - f0) / (f1 - f0)                   # interpolated weeks observed (1-based)
    }, numeric(1))
    incr <- c(frac[1], diff(frac))
    mean_delay <- sum((seq_along(frac) - 1L) * incr)    # mean delay in weeks

    ids <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[1]
    row <- data.table::data.table(ids, n_settled = sum(keep),
             mean_delay = round(mean_delay, 2),
             complete_by_md = round(frac[length(frac)], 3))
    for (i in seq_along(probs)) row[[paste0("w", probs[i] * 100)]] <- round(wto[i], 1)
    out[[tsid]] <- row
  }
  data.table::rbindlist(out, fill = TRUE)
}
