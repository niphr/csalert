# csfmt_reporting_triangle_v3: the nowcast INPUT format.
#
# Aggregated counts on a reference x reporting grid + full identity. The
# reference axis is an ISO week; the reporting axis is the calendar date the
# count arrived, so the delay is a number of days. Semantically dense (absent
# observed cell == 0) but stored sparse (zeros implied); the as-of boundary (max
# reporting date) disambiguates implied-zero from not-yet-reported.
# Densification into the ref x delay working matrix happens here
# (reporting_triangle_matrix), bounded by max_delay_days. The constructor does
# not densify, because max_delay_days is a nowcast parameter.

# The Monday that starts an ISO week, as a Date. cstime 2025.10.13 exports no
# isoyearweek_to_first_date(), so read the mon column of its calendar table.
# as.Date() pins the class: every delay is days between two Date vectors, and a
# mixed Date/IDate comparison is silent rather than an error.

#' The Monday that starts an ISO week
#'
#' Returns the Monday that starts each ISO week, as a `Date`. Every delay in a
#' reporting triangle counts days from this Monday.
#' @param isoyearweek A character vector of ISO weeks, written `"YYYY-WW"`.
#' @returns A `Date` vector as long as `isoyearweek`, with `NA` for a value that
#'   is not an ISO week in `cstime::dates_by_isoyearweek`.
#' @family reporting triangle functions
#' @seealso `vignette("pipeline", package = "csalert")`, which counts every delay
#'   and age in days from this Monday.
#' @examples
#' # ISO week 2026-01 starts on Monday 2025-12-29
#' isoyearweek_week_start(c("2026-01", "2026-02"))
#'
#' # a report on 2026-01-08 has delay day 10 in reference week 2026-01
#' as.Date("2026-01-08") - isoyearweek_week_start("2026-01")
#'
#' # a string that is not an ISO week gives NA
#' isoyearweek_week_start("2026-99")
#' @export
isoyearweek_week_start <- function(isoyearweek) {
  cal <- cstime::dates_by_isoyearweek
  return(as.Date(cal$mon[match(isoyearweek, cal$isoyearweek)]))
}

#' Build a csfmt_reporting_triangle_v3
#'
#' Builds the input of the nowcast engines: counts by reference ISO week and by
#' the date each count was reported. The newest reporting date is the as-of
#' boundary.
#'
#' The triangle is sparse. An absent cell on or before the as-of date is a zero,
#' and a cell after it is not reported yet. The constructor copies `data` and adds
#' the ids of [set_time_series_id()]. It stops with an error when a reporting date
#' comes before its reference Monday, or a count is negative.
#' @param data A data.table with the identity, reference, reporting and count
#'   columns.
#' @param id_cols The identity columns that define one series.
#' @param reference_col The reference ISO-week column, written `"YYYY-WW"`.
#' @param reporting_col The column with the date each count was reported. Its
#'   class MUST be exactly `Date`, so an `IDate` is an error. It MUST NOT hold
#'   `NA`. One `NA` would make the as-of boundary `NA`. Every nowcast engine
#'   would then return the observed totals with no warning.
#' @param value_col The count column.
#' @returns A `csfmt_reporting_triangle_v3`: a data.table with the attributes
#'   `as_of`, a `Date`, and `id_cols`, `reference_col`, `reporting_col` and
#'   `value_col`.
#' @family reporting triangle functions
#' @seealso `vignette("pipeline", package = "csalert")`, which takes a triangle
#'   through the whole pipeline.
#' @examples
#' # 40 reference weeks, each reported 3, 10 and 17 days after its Monday. The
#' # data stops at one as-of date, so the newest weeks are still incomplete.
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
#'
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' # the as-of boundary is the newest reporting date in the data
#' attr(tri, "as_of")
#' head(tri, 3)
#' @export
csfmt_reporting_triangle_v3 <- function(
  data,
  id_cols,
  reference_col = "isoyearweek_reference",
  reporting_col = "reporting_date",
  value_col = "numerator"
) {
  stopifnot(
    data.table::is.data.table(data),
    all(id_cols %in% names(data)),
    all(c(reference_col, reporting_col, value_col) %in% names(data))
  )
  # Strict on the class, not on inheritance. IDate inherits from Date, so an
  # inherits(x, "Date") check accepts it, and an IDate then compares against a
  # Date without erroring.
  if (!identical(class(data[[reporting_col]]), "Date")) {
    stop(
      "`",
      reporting_col,
      "` must be a Date column, not ",
      paste(class(data[[reporting_col]]), collapse = "/"),
      call. = FALSE
    )
  }
  # ONE missing reporting date poisons the whole triangle, silently. `max()` of
  # a Date vector holding an NA is NA, measured 2026-09-22, so `as_of` becomes
  # NA. Then no reference week settles, no delay pool builds, and every nowcast
  # engine returns the observed totals while still labelling them a nowcast.
  # Densification drops the row as well, so the week's observed count is
  # understated too. Error here, and name the count.
  n_missing <- sum(is.na(data[[reporting_col]]))
  if (n_missing > 0L) {
    stop(
      "`",
      reporting_col,
      "` has ",
      n_missing,
      " missing value(s). Map every missing reporting date to a date, or drop ",
      "those rows, before you build the triangle.",
      call. = FALSE
    )
  }
  d <- data.table::copy(data)
  week_start <- isoyearweek_week_start(d[[reference_col]])
  # NA-safe: a missing reference week is not a reporting-before-reference
  # violation. It carries no delay info. Only flag genuine negative-delay rows.
  if (any(d[[reporting_col]] < week_start, na.rm = TRUE)) {
    stop("reporting date is before reference week start", call. = FALSE)
  }
  if (any(d[[value_col]] < 0, na.rm = TRUE)) {
    stop("negative counts in the reporting triangle", call. = FALSE)
  }

  set_time_series_id(d, id_cols)
  data.table::setattr(d, "id_cols", id_cols)
  data.table::setattr(d, "as_of", max(d[[reporting_col]]))
  data.table::setattr(d, "reference_col", reference_col)
  data.table::setattr(d, "reporting_col", reporting_col)
  data.table::setattr(d, "value_col", value_col)
  data.table::setattr(
    d,
    "class",
    unique(c("csfmt_reporting_triangle_v3", class(d)))
  )
  return(d[])
}

#' Turn a reporting triangle into one count matrix per series
#'
#' Returns, for each series, a matrix of counts with one row per reference week
#' and one column per delay day. Every nowcast engine calls it first.
#'
#' The rows run over every ISO week from the first to the last reference week.
#' A week with no report is a row of zeros. The last column also holds every
#' later delay, so a late report adds to `rowSums(mat)`. A report before its
#' reference Monday has a negative delay, and is dropped.
#' @param triangle The `csfmt_reporting_triangle_v3` to turn into matrices.
#' @param max_delay_days The number of delay columns, in days. With 35, the
#'   columns are delay days 0 to 34, and a report at delay 35 or 400 counts in
#'   column `"34"`.
#' @param value_col The count column. The default is the `value_col` of the
#'   triangle. Give a denominator column to get its matrix.
#' @returns A list named by `time_series_id`. Each element holds `reference`, the
#'   ISO weeks of the rows, and `mat`, the matrix. A cell sums its counts with
#'   `na.rm = TRUE`, so a cell with only `NA` counts is 0.
#' @family reporting triangle functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 3, which reads the
#'   delay distribution from these counts.
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
#' tri <- csfmt_reporting_triangle_v3(
#'   d,
#'   id_cols = c("indicator_tag", "location_code", "age", "sex")
#' )
#'
#' m <- reporting_triangle_matrix(tri, max_delay_days = 21)
#' names(m)
#'
#' # rows are reference weeks, columns are delay days 0 to 20
#' dim(m[[1]]$mat)
#' head(m[[1]]$reference, 3)
#'
#' # this series reports on days 3, 10 and 17 after the reference Monday
#' m[[1]]$mat[1:3, c("3", "10", "17")]
#'
#' # the newest weeks are only partly reported: the later delays are still zero
#' tail(m[[1]]$mat[, c("3", "10", "17")], 3)
#' @export
reporting_triangle_matrix <- function(
  triangle,
  max_delay_days,
  value_col = attr(triangle, "value_col")
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  .delay <- .ref <- time_series_id <- NULL
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  ref_col <- attr(triangle, "reference_col")
  rep_col <- attr(triangle, "reporting_col")
  val_col <- value_col

  d <- data.table::as.data.table(triangle)
  d[, .ref := get(ref_col)]
  # delay in DAYS from the reference week's Monday, so a report on that Monday
  # has delay 0
  d[,
    .delay := as.integer(
      get(rep_col) - isoyearweek_week_start(get(ref_col))
    )
  ]
  # A report at delay max_delay_days or later counts in the LAST delay column,
  # max_delay_days - 1. It is not dropped. The observed count is rowSums() of
  # this matrix, so a drop removed every late report from it. Measured
  # 2026-09-23 in luftveisovervaking_trend, the drop removed the whole SARI
  # history 2020-01 to 2025-26, which was bulk-loaded on 2025-07-30. The cap
  # runs before the filter, so a negative delay stays dropped.
  d[.delay >= max_delay_days, .delay := max_delay_days - 1L]
  d <- d[.delay >= 0]

  all_weeks <- cstime::dates_by_isoyearweek$isoyearweek
  delay_cols <- as.character(0:(max_delay_days - 1))

  out <- list()
  for (tsid in unique(d$time_series_id)) {
    ds <- d[time_series_id == tsid]
    # na.rm = TRUE reaches sum() through dcast's `...`. Without it, one NA
    # count made sum() return NA for its cell. The NA fill below then set that
    # cell to 0, so every real count in the cell was lost, with no warning.
    m <- data.table::dcast.data.table(
      ds,
      .ref ~ .delay,
      value.var = val_col,
      fun.aggregate = sum,
      na.rm = TRUE,
      fill = 0
    )
    for (k in delay_cols) {
      if (!k %in% names(m)) m[, (k) := 0]
    } # complete delay axis

    # complete the reference axis: contiguous weeks min..max (fills interior gaps
    # and zero-case weeks), so the nowcast truncation works on contiguous rows
    i1 <- match(min(m$.ref), all_weeks)
    i2 <- match(max(m$.ref), all_weeks)
    full <- data.table::data.table(.ref = all_weeks[i1:i2])
    m <- m[full, on = ".ref"]
    for (k in delay_cols) {
      m[is.na(get(k)), (k) := 0]
    }

    data.table::setcolorder(m, c(".ref", delay_cols))
    out[[tsid]] <- list(
      reference = m$.ref,
      mat = as.matrix(m[, delay_cols, with = FALSE])
    )
  }
  return(out)
}
