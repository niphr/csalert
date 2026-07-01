# reporting_completion: the empirical reporting-delay summary of a triangle --
# "how long until a reference week's cases are (nearly) all in".
#
# From the SETTLED weeks (old enough to know their final total -- else the
# right-truncation makes recent weeks look more complete than they are), pool the
# cumulative fraction reported by each delay, then read off: the mean delay, and
# the delay ECDF evaluated at each DISCRETE weeks-observed -- pct_wN = the pooled %
# of a reference week's cases in once it has been observed for N weeks (N=1 is only
# its delay-0 reports). No interpolation: these are the step heights themselves.
# complete_by_md (= pct at max_delay / 100) < 1 means reporting still dribbles in
# past the horizon -- itself a signal.
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
#' @param period Time stratification of the settled weeks, by the calendar year /
#'   month of each week's Thursday: `"all"` (one pooled curve, default),
#'   `"year"`, or `"month"` (one row per period). Use `"year"`/`"month"` to see
#'   whether completion time is trending up or down.
#' @returns One row per series (and per period when stratified): identity columns
#'   + `period` + `n_settled`, `mean_delay`, `complete_by_md` (fraction in by
#'   `max_delay`), and `pct_w1`..`pct_w<max_delay>` (the pooled \% of cases reported
#'   after that many weeks observed -- the delay ECDF, no interpolation).
#' @export
reporting_completion <- function(triangle, max_delay, delay_window = NULL,
                                 period = c("all", "year", "month")) {
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
  plabel <- switch(period,
    all   = rep("all", length(weeks)),
    year  = as.character(dbi$isoyear),
    month = format(dbi$thu, "%Y-%m"))       # dbi$thu = the week's midweek day

  # completion summary for one block of settled weeks (rows = reference weeks,
  # cols = delays 0..max_delay-1); NULL when too few non-empty weeks to trust.
  summarise <- function(M) {
    tot <- rowSums(M); ok <- tot > 0
    if (sum(ok) < 3L) return(NULL)
    cum  <- t(apply(M[ok, , drop = FALSE], 1, cumsum))
    frac <- colSums(cum) / sum(tot[ok])                 # pooled cumulative fraction by delay
    incr <- c(frac[1], diff(frac))
    row <- data.table::data.table(n_settled = sum(ok),
             mean_delay = round(sum((seq_along(frac) - 1L) * incr), 2),  # mean delay in weeks
             complete_by_md = round(frac[length(frac)], 3))
    # the delay ECDF read at each DISCRETE weeks-observed: pct_wN = pooled % of a
    # reference week's cases reported once it has been observed for N weeks
    # (N = delay + 1). No interpolation -- these are the step heights themselves.
    for (i in seq_along(frac)) row[[paste0("pct_w", i)]] <- round(frac[i] * 100, 1)
    row
  }

  out <- list()
  for (tsid in names(rts)) {
    refs <- rts[[tsid]]$reference; mat <- rts[[tsid]]$mat
    age <- as_of_i - match(refs, weeks)
    keep <- age >= (max_delay - 1L)
    if (!is.null(delay_window)) keep <- keep & age < (delay_window + max_delay)
    if (!any(keep)) next
    M <- mat[keep, , drop = FALSE]
    per <- plabel[match(refs[keep], weeks)]
    ids <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[1]
    for (pv in sort(unique(per))) {                     # one summary per period slice
      s <- summarise(M[per == pv, , drop = FALSE])
      if (is.null(s)) next
      out[[paste(tsid, pv)]] <- data.table::data.table(ids, period = pv, s)
    }
  }
  data.table::rbindlist(out, fill = TRUE)
}
