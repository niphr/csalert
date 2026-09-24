# compare_results / qc_week_over_week_v1: compare two collapsed csfmt result sets.
#
# The shared core (compare_results) joins two runs on the content-hash
# time_series_id + isoyearweek (the hash is stable across runs, so the same
# series matches) and returns a long, grammar-tagged diff -- one row per
# (series, week, value column) with `cur`/`prv`. It auto-detects the value
# columns and their roles via csfmt_interpret, so nothing is hardcoded.
#
# qc_week_over_week_v1 splits that diff at the nowcast horizon:
#   A) integrity: settled weeks (>= max_delay_weeks behind last run's frontier)
#      should be identical -- any continuous-median change is flagged. Ideally
#      empty.
#   B) signal: frontier weeks (the still-revising window + the new week) -- the
#      ordinal status transitions, including the new week.
#
# THE HORIZON HERE IS IN WEEKS, and the parameter is named max_delay_weeks for
# that reason. It indexes an ISO-week vector, so it windows REFERENCE WEEKS and
# never delay days. The nowcast engines take max_delay_days, in DAYS, because
# the triangle's reporting axis is a calendar date. Two names for two units is
# deliberate: one name meaning days in one function and weeks in another is the
# defect the whole rename exists to prevent.

#' Compare two collapsed result sets, column by column
#'
#' Joins two runs on `time_series_id` and `isoyearweek`, and returns one row per
#' series, week and value column. [csfmt_interpret()] finds the value columns of
#' `current`, and the parts of each name.
#'
#' `time_series_id` is a hash of the identity columns, so a series has the same id
#' in both runs. A week in only one run gets `NA` for the other run.
#' @param current,previous The output of [ens_collapse()] for two runs.
#' @returns A long data.table with `time_series_id`, `isoyearweek`, the columns
#'   among `indicator_tag`, `location_code`, `age` and `sex` that exist, and:
#' * `column`: the name of the value column,
#' * `cur`, `prv`: its value in `current` and in `previous`,
#' * `role`, `q`, `level`: the parts of its name.
#' @section Identity columns MUST use the csfmt schema names:
#' [csfmt_interpret()] reads every column outside the csfmt schema as a value
#' column. `location_code` and `indicator_tag` are schema names, but `location`
#' and `indicator` are not. So with `location` or `indicator`, `cur` and `prv`
#' become character.
#'
#' This function still returns a table. [qc_week_over_week_v1()] then stops with
#' `non-numeric argument to binary operator`.
#' @family quality control functions
#' @seealso `vignette("pipeline", package = "csalert")`, section 9.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday
#' mondays <- as.Date("2023-01-02") + 7 * (0:39)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(rep(mondays, each = 3), "%G-%V"),
#'   reporting_date = rep(mondays, each = 3) + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= mondays[40] + 6]
#'
#' id <- c("indicator_tag", "location_code", "age", "sex")
#'
#' # Set the seed inside `run()`. Then the two runs differ only by the data
#' # revision, and not by their Monte-Carlo draws.
#' run <- function(x) {
#'   set.seed(2)
#'   ens_collapse(nowcast_delay_ecdf_v1(
#'     csfmt_reporting_triangle_v3(x, id_cols = id),
#'     max_delay_days = 21, n_sim = 200
#'   ))
#' }
#'
#' # last week's run saw one reference week before a correction raised it
#' cur <- run(d)
#' d_prv <- data.table::copy(d)
#' d_prv[
#'   isoyearweek_reference == format(mondays[11], "%G-%V"),
#'   numerator := numerator - 5
#' ]
#' prv <- run(d_prv)
#'
#' # with the seed held fixed, only the corrected week moves
#' compare_results(cur, prv)[q == 0.5 & abs(cur - prv) > 0]
#' @export
compare_results <- function(current, previous) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  i.level <- i.q <- i.role <- NULL
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
    return(data.table::data.table(
      m[, c(key, idc), with = FALSE],
      column = col,
      cur = if (cc %in% names(m)) m[[cc]] else NA_real_,
      prv = if (pc %in% names(m)) m[[pc]] else NA_real_
    ))
  })
  long <- data.table::rbindlist(chunks)
  long[interp, on = "column", `:=`(role = i.role, q = i.q, level = i.level)]
  return(long[])
}

#' Compare this week's run with last week's run
#'
#' Splits the output of [compare_results()] at the nowcast horizon. `$integrity`
#' lists the settled weeks whose median changed, and `$signal` lists the status
#' changes in the newer weeks.
#'
#' A week is settled when it is at least `max_delay_weeks` ISO weeks older than the
#' newest week of `previous`. A row in `$integrity` means that a published number
#' for a settled week changed, so ideally that table is empty. It compares finite
#' values only. `$signal` counts a new week as a change. Both tables use the
#' median, `q = 0.5`.
#' @param current,previous The output of [ens_collapse()] for this run and for the
#'   previous run. Their identity columns MUST have the names that
#'   [compare_results()] needs.
#' @param max_delay_weeks The nowcast horizon in ISO weeks. The engines take
#'   `max_delay_days`, in days. The names differ so that one name never means two
#'   units.
#' @param status_roles The roles that hold an ordinal status. `$signal` holds only
#'   these roles, and `$integrity` leaves them out. The default holds `"status"`
#'   from [mem_thresholds_v1()] and `"hlmstatus"` from [signal_detection_hlm()].
#' @param tol The largest change in a settled median that counts as no change.
#' @returns A list of two data.tables:
#' * `integrity`, with `indicator_tag`, `isoyearweek`, `column`, `prv`, `cur`
#'   and `abs_diff`,
#' * `signal`, with `indicator_tag`, `isoyearweek`, `column`, `from`, `to` and
#'   `change`, which is `"new"` or `"changed"`.
#'
#' A table with no rows keeps `prv` and `cur`, and has no added column.
#' `indicator_tag` is there only when the input has it.
#' @family quality control functions
#' @seealso `vignette("pipeline", package = "csalert")`, section 9.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday
#' mondays <- as.Date("2023-01-02") + 7 * (0:39)
#' set.seed(1)
#' d <- data.table::data.table(
#'   isoyearweek_reference = format(rep(mondays, each = 3), "%G-%V"),
#'   reporting_date = rep(mondays, each = 3) + rep(c(3, 10, 17), 40),
#'   numerator = rpois(120, c(30, 15, 5)),
#'   indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
#' )
#' d <- d[reporting_date <= mondays[40] + 6]
#'
#' id <- c("indicator_tag", "location_code", "age", "sex")
#'
#' # set the seed inside `run()`, so the two runs differ only by the data
#' run <- function(x) {
#'   set.seed(2)
#'   ens_collapse(nowcast_delay_ecdf_v1(
#'     csfmt_reporting_triangle_v3(x, id_cols = id),
#'     max_delay_days = 21, n_sim = 200
#'   ))
#' }
#'
#' cur <- run(d)
#' d_prv <- data.table::copy(d)
#' d_prv[
#'   isoyearweek_reference == format(mondays[11], "%G-%V"),
#'   numerator := numerator - 5
#' ]
#' prv <- run(d_prv)
#'
#' # the engine horizon is 21 days, and this horizon is 3 weeks
#' qc <- qc_week_over_week_v1(cur, prv, max_delay_weeks = 3)
#'
#' # the corrected week is settled, so its changed median is listed here
#' qc$integrity
#'
#' # empty: these runs hold no status column, because neither
#' # mem_thresholds_v1() nor signal_detection_hlm() ran
#' qc$signal
#' @export
qc_week_over_week_v1 <- function(
  current,
  previous,
  max_delay_weeks,
  tol = 1e-6,
  status_roles = c("status", "hlmstatus")
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  abs_diff <- change <- cur <- from <- isoyearweek <- level <- prv <- role <- NULL
  long <- compare_results(current, previous)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  latest_prev <- max(data.table::as.data.table(previous)$isoyearweek)
  cutoff <- weeks[match(latest_prev, weeks) - max_delay_weeks] # weeks <= this are settled

  # A) integrity: settled weeks, continuous medians, changed beyond tol -> flag
  A <- long[
    isoyearweek <= cutoff &
      !is.na(q) &
      q == 0.5 &
      is.na(level) &
      (is.na(role) | !(role %in% status_roles)) &
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
      role %in% status_roles &
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

  return(list(integrity = A[], signal = B[]))
}
