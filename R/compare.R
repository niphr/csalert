# compare_results / qc_week_over_week_v1: compare two collapsed csfmt result sets.
#
# The shared core (compare_results) joins two runs on the content-hash
# time_series_id + isoyearweek (the hash is stable across runs, so the same
# series matches) and returns a long, grammar-tagged diff -- one row per
# (series, week, value column) with `cur`/`prv`. It auto-detects the value
# columns and their roles via csfmt_interpret, so nothing is hardcoded.
#
# qc_week_over_week_v1 splits that diff at the nowcast horizon:
#   A) integrity: settled weeks (>= max_delay behind last run's frontier) should
#      be identical -- any continuous-median change is flagged. Ideally empty.
#   B) signal: frontier weeks (the still-revising window + the new week) -- the
#      ordinal status transitions, including the new week.

#' Compare two collapsed csfmt result sets
#' @param current,previous data.tables (or csfmt_rts_data_v3) from two runs.
#' @returns A long data.table: identity + isoyearweek + column + role/q/level +
#'   `cur`/`prv`.
#' @section Identity columns MUST use the csfmt schema names:
#' The value columns are found with \code{\link{csfmt_interpret}}, which treats
#' anything outside the csfmt structural schema as a value column. Key the two
#' runs on schema names such as `location_code` and `indicator_tag`.
#'
#' A non-schema identity column is a silent trap. `location` and `indicator` are
#' NOT in the schema (`location_code` and `indicator_tag` are), so they are read
#' as value columns; their character values are then stacked with the numeric
#' measures and `cur`/`prv` come back as character for every row. This function
#' still returns a table, so the damage is easy to miss. But
#' \code{\link{qc_week_over_week_v1}} then evaluates `abs(cur - prv)` on that
#' character column and FAILS with
#' `Error in cur - prv : non-numeric argument to binary operator`.
#'
#' Note that `vignette("nowcasting", package = "csalert")` builds its triangle
#' with `id_cols = c("indicator", "location", "age", "sex")`. Those names work
#' for the nowcast pipeline itself, but a run-over-run comparison of the result
#' needs `indicator_tag` and `location_code`.
#' @seealso Neither package vignette covers run-over-run comparison.
#'   \code{\link{qc_week_over_week_v1}} is the usual entry point; it splits this
#'   diff at the nowcast horizon.
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
#'
#' id <- c("indicator_tag", "location_code", "age", "sex")
#'
#' # The engine is stochastic, so reset the seed inside `run()`. Without that,
#' # the two runs would also differ by their Monte-Carlo draws and the diff would
#' # confound sampling noise with the actual data revision.
#' run <- function(x) {
#'   set.seed(2)
#'   ens_collapse(nowcast_quasipoisson_v1(
#'     csfmt_reporting_triangle_v3(x, id_cols = id),
#'     max_delay = 3, n_sim = 200
#'   ))
#' }
#'
#' # last week's run saw one reference week before it was corrected upward
#' cur <- run(d)
#' d_prv <- data.table::copy(d)
#' d_prv[isoyearweek_reference == w[i + 10], numerator := numerator - 5]
#' prv <- run(d_prv)
#'
#' # one row per (series, week, value column). With the seed held fixed, the only
#' # week that moves is the corrected one.
#' compare_results(cur, prv)[q == 0.5 & abs(cur - prv) > 0]
#' @export
compare_results <- function(current, previous) {
  cur <- data.table::as.data.table(current)
  prv <- data.table::as.data.table(previous)
  interp <- csfmt_interpret(cur)
  cols <- interp$column
  key <- c("time_series_id", "isoyearweek")
  idc <- intersect(
    c("indicator_tag", "location_code", "age", "sex"),
    names(cur)
  )

  m <- merge(
    cur[, c(key, idc, intersect(cols, names(cur))), with = FALSE],
    prv[, c(key, intersect(cols, names(prv))), with = FALSE],
    by = key,
    suffixes = c(".cur", ".prv"),
    all = TRUE
  )

  chunks <- lapply(cols, function(col) {
    cc <- paste0(col, ".cur")
    pc <- paste0(col, ".prv")
    if (!cc %in% names(m) && !pc %in% names(m)) {
      return(NULL)
    }
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
#' @seealso Neither package vignette covers run-over-run comparison.
#'   \code{\link{compare_results}} is the underlying diff, and documents which
#'   identity column names this check needs.
#'   \code{\link{qc_surveillance_data_v1}} answers a different question, about one
#'   input feed rather than two finished runs.
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
#'
#' id <- c("indicator_tag", "location_code", "age", "sex")
#'
#' # seed inside `run()`, so the two runs differ only by the data revision and
#' # not by their Monte-Carlo draws
#' run <- function(x) {
#'   set.seed(2)
#'   ens_collapse(nowcast_quasipoisson_v1(
#'     csfmt_reporting_triangle_v3(x, id_cols = id),
#'     max_delay = 3, n_sim = 200
#'   ))
#' }
#'
#' cur <- run(d)
#' d_prv <- data.table::copy(d)
#' d_prv[isoyearweek_reference == w[i + 10], numerator := numerator - 5]
#' prv <- run(d_prv)
#'
#' qc <- qc_week_over_week_v1(cur, prv, max_delay = 3)
#'
#' # A settled week whose published median moved between runs. This table is
#' # ideally empty; a row in it means history was rewritten.
#' qc$integrity
#'
#' # Status transitions on the frontier weeks. Empty here because these runs have
#' # no status column at all: only mem_thresholds_v1() writes role "status", and
#' # it was not run. NOTE signal_detection_hlm() does NOT qualify -- it writes
#' # role "hlmstatus", which this check does not select, so HLM transitions never
#' # appear here.
#' qc$signal
#' @export
qc_week_over_week_v1 <- function(current, previous, max_delay, tol = 1e-6) {
  long <- compare_results(current, previous)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  latest_prev <- max(data.table::as.data.table(previous)$isoyearweek)
  cutoff <- weeks[match(latest_prev, weeks) - max_delay] # weeks <= this are settled

  # A) integrity: settled weeks, continuous medians, changed beyond tol -> flag
  A <- long[
    isoyearweek <= cutoff &
      !is.na(q) &
      q == 0.5 &
      is.na(level) &
      (is.na(role) | role != "status") &
      is.finite(cur) &
      is.finite(prv) &
      abs(cur - prv) > tol
  ]
  A <- A[,
    .SD,
    .SDcols = intersect(
      c("indicator_tag", "isoyearweek", "column", "prv", "cur"),
      names(A)
    )
  ]
  if (nrow(A)) {
    A[, abs_diff := abs(cur - prv)]
  }

  # B) signal: frontier weeks, ordinal status median, transitions incl. new week
  B <- long[
    isoyearweek > cutoff &
      role == "status" &
      !is.na(q) &
      q == 0.5 &
      !is.na(cur) &
      ((is.na(prv)) | (prv != cur))
  ]
  B <- B[,
    .SD,
    .SDcols = intersect(
      c("indicator_tag", "isoyearweek", "column", "prv", "cur"),
      names(B)
    )
  ]
  if (nrow(B)) {
    data.table::setnames(
      B,
      c("prv", "cur"),
      c("from", "to"),
      skip_absent = TRUE
    )
    B[, change := data.table::fifelse(is.na(from), "new", "changed")]
  }

  list(integrity = A[], signal = B[])
}
