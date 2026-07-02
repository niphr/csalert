# compare_results / qc_week_over_week: compare two collapsed csfmt result sets.
#
# The shared core (compare_results) joins two runs on the content-hash
# time_series_id + isoyearweek (the hash is stable across runs, so the same
# series matches) and returns a long, grammar-tagged diff -- one row per
# (series, week, value column) with `cur`/`prv`. It auto-detects the value
# columns and their roles via csfmt_interpret, so nothing is hardcoded.
#
# qc_week_over_week splits that diff at the nowcast horizon:
#   A) integrity: settled weeks (>= max_delay behind last run's frontier) should
#      be identical -- any continuous-median change is flagged. Ideally empty.
#   B) signal: frontier weeks (the still-revising window + the new week) -- the
#      ordinal status transitions, including the new week.

#' Compare two collapsed csfmt result sets
#' @param current,previous data.tables (or csfmt_rts_data_v3) from two runs.
#' @returns A long data.table: identity + isoyearweek + column + role/q/level +
#'   `cur`/`prv`.
#' @export
compare_results <- function(current, previous) {
  cur <- data.table::as.data.table(current)
  prv <- data.table::as.data.table(previous)
  interp <- csfmt_interpret(cur)
  cols <- interp$column
  key  <- c("time_series_id", "isoyearweek")
  idc  <- intersect(c("indicator_tag", "location_code", "age", "sex"), names(cur))

  m <- merge(
    cur[, c(key, idc, intersect(cols, names(cur))), with = FALSE],
    prv[, c(key, intersect(cols, names(prv))), with = FALSE],
    by = key, suffixes = c(".cur", ".prv"), all = TRUE
  )

  chunks <- lapply(cols, function(col) {
    cc <- paste0(col, ".cur"); pc <- paste0(col, ".prv")
    if (!cc %in% names(m) && !pc %in% names(m)) return(NULL)
    data.table::data.table(
      m[, c(key, idc), with = FALSE],
      column = col,
      cur = if (cc %in% names(m)) m[[cc]] else NA_real_,
      prv = if (pc %in% names(m)) m[[pc]] else NA_real_
    )
  })
  long <- data.table::rbindlist(chunks)
  long[interp, on = "column", `:=`(role = i.role, q = i.q, level = i.level)]
  long[]
}

#' Week-over-week QC: settled-data integrity (A) + frontier status signal (B)
#' @param current,previous Two runs' collapsed csfmt.
#' @param max_delay Nowcast horizon (weeks); sets the settled/frontier boundary.
#' @param tol Tolerance for "unchanged" in the integrity check.
#' @returns `list(integrity = <A>, signal = <B>)`.
#' @export
qc_week_over_week <- function(current, previous, max_delay, tol = 1e-6) {
  long <- compare_results(current, previous)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  latest_prev <- max(data.table::as.data.table(previous)$isoyearweek)
  cutoff <- weeks[match(latest_prev, weeks) - max_delay]   # weeks <= this are settled

  # A) integrity: settled weeks, continuous medians, changed beyond tol -> flag
  A <- long[isoyearweek <= cutoff & !is.na(q) & q == 0.5 & is.na(level) &
              (is.na(role) | role != "status") &
              is.finite(cur) & is.finite(prv) & abs(cur - prv) > tol]
  A <- A[, .SD, .SDcols = intersect(
    c("indicator_tag", "isoyearweek", "column", "prv", "cur"), names(A))]
  if (nrow(A)) A[, abs_diff := abs(cur - prv)]

  # B) signal: frontier weeks, ordinal status median, transitions incl. new week
  B <- long[isoyearweek > cutoff & role == "status" & !is.na(q) & q == 0.5 &
              !is.na(cur) & ((is.na(prv)) | (prv != cur))]
  B <- B[, .SD, .SDcols = intersect(
    c("indicator_tag", "isoyearweek", "column", "prv", "cur"), names(B))]
  if (nrow(B)) {
    data.table::setnames(B, c("prv", "cur"), c("from", "to"), skip_absent = TRUE)
    B[, change := data.table::fifelse(is.na(from), "new", "changed")]
  }

  list(integrity = A[], signal = B[])
}
