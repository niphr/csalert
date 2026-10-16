# csfmt_reporting_triangle_v4: the input of the v4 nowcast engines. A copy of
# csfmt_reporting_triangle_v3 under its own class. The reference axis is an
# ISO week, and the reporting axis is the date the count arrived, so a delay
# is a number of days. The triangle is sparse: an absent cell on or before the
# as-of date is a zero.

#' Build a csfmt_reporting_triangle_v4
#'
#' Builds the input of the v4 nowcast engines: counts by reference ISO week and
#' by the date each count was reported. The newest reporting date is the as-of
#' date.
#'
#' The constructor copies `data` and adds `time_series_id` and
#' `time_series_label`. It stops with an error when a reporting date comes
#' before its reference Monday, or when a count is negative.
#' @param data A data.table with the identity, reference, reporting and count
#'   columns.
#' @param id_cols The identity columns that define one series.
#' @param reference_col The reference ISO-week column, written `"YYYY-WW"`.
#' @param reporting_col The column with the date each count was reported. Its
#'   class MUST be exactly `Date`, and it MUST NOT hold `NA`.
#' @param value_col The count column.
#' @returns A `csfmt_reporting_triangle_v4`: a data.table with the attributes
#'   `as_of`, a `Date`, and `id_cols`, `reference_col`, `reporting_col` and
#'   `value_col`.
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
#' attr(tri, "as_of")
#' @export
csfmt_reporting_triangle_v4 <- function(
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
  # Strict on the class: an IDate inherits from Date, and then compares
  # against a Date with no error.
  if (!identical(class(data[[reporting_col]]), "Date")) {
    stop(
      "`",
      reporting_col,
      "` must be a Date column, not ",
      paste(class(data[[reporting_col]]), collapse = "/"),
      call. = FALSE
    )
  }
  # One NA reporting date makes the as-of date NA, and then no week settles.
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
  week_start <- .v4_isoyearweek_week_start(d[[reference_col]])
  if (any(d[[reporting_col]] < week_start, na.rm = TRUE)) {
    stop("reporting date is before reference week start", call. = FALSE)
  }
  if (any(d[[value_col]] < 0, na.rm = TRUE)) {
    stop("negative counts in the reporting triangle", call. = FALSE)
  }

  .v4_set_time_series_id(d, id_cols)
  data.table::setattr(d, "id_cols", id_cols)
  data.table::setattr(d, "as_of", max(d[[reporting_col]]))
  data.table::setattr(d, "reference_col", reference_col)
  data.table::setattr(d, "reporting_col", reporting_col)
  data.table::setattr(d, "value_col", value_col)
  data.table::setattr(
    d,
    "class",
    unique(c("csfmt_reporting_triangle_v4", class(d)))
  )
  return(d[])
}

# A copy of reporting_triangle_matrix(): for each series, a matrix with one
# row per reference week, from the first to the last, and one column per
# delay day 0 to max_delay_days - 1. A report at delay max_delay_days or later
# goes to `late`, one value per row. A negative delay is dropped. A cell sums
# its counts with na.rm = TRUE.
.v4_reporting_triangle_matrix <- function(
  triangle,
  max_delay_days,
  value_col = attr(triangle, "value_col")
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  .delay <- .ref <- time_series_id <- NULL
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v4"))
  ref_col <- attr(triangle, "reference_col")
  rep_col <- attr(triangle, "reporting_col")

  d <- data.table::as.data.table(triangle)
  d[, .ref := get(ref_col)]
  d[,
    .delay := as.integer(
      get(rep_col) - .v4_isoyearweek_week_start(get(ref_col))
    )
  ]
  d <- d[.delay >= 0]
  d[.delay > max_delay_days, .delay := as.integer(max_delay_days)]

  all_weeks <- cstime::dates_by_isoyearweek$isoyearweek
  delay_cols <- as.character(0:(max_delay_days - 1))
  late_col <- as.character(max_delay_days)
  fill_cols <- c(delay_cols, late_col)

  out <- list()
  for (tsid in unique(d$time_series_id)) {
    m <- data.table::dcast.data.table(
      d[time_series_id == tsid],
      .ref ~ .delay,
      value.var = value_col,
      fun.aggregate = sum,
      na.rm = TRUE,
      fill = 0
    )
    for (k in setdiff(fill_cols, names(m))) {
      m[, (k) := 0]
    }
    # every week from the first to the last reference week, so that a week
    # with no report is a row of zeros
    i1 <- match(min(m$.ref), all_weeks)
    i2 <- match(max(m$.ref), all_weeks)
    m <- m[data.table::data.table(.ref = all_weeks[i1:i2]), on = ".ref"]
    for (k in fill_cols) {
      m[is.na(get(k)), (k) := 0]
    }
    data.table::setcolorder(m, c(".ref", delay_cols))
    out[[tsid]] <- list(
      reference = m$.ref,
      mat = as.matrix(m[, delay_cols, with = FALSE]),
      late = as.numeric(m[[late_col]])
    )
  }
  return(out)
}

# The rows of `$data` of a nowcast: the identity columns, `isoyearweek` and
# `original`, the observed total rowSums(mat) + late of each reference week.
.v4_triangle_frame <- function(x, rts) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  isoyearweek <- original <- time_series_id <- NULL
  id_cols <- attr(x, "id_cols")
  d_tri <- data.table::as.data.table(x)
  rows <- lapply(names(rts), function(tsid) {
    refs <- rts[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(
      1L,
      length(refs)
    )]
    idvals[, isoyearweek := refs]
    idvals[, original := rowSums(rts[[tsid]]$mat) + rts[[tsid]]$late]
    return(idvals)
  })
  return(data.table::rbindlist(rows))
}

# The observed total rowSums(mat) + late of every row, over every series in
# the order of `series_ids`.
.v4_observed_total <- function(rts, series_ids) {
  return(unlist(lapply(series_ids, function(tsid) {
    return(rowSums(rts[[tsid]]$mat) + rts[[tsid]]$late)
  })))
}
