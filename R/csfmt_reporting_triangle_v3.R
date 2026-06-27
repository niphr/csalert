# csfmt_reporting_triangle_v3: the nowcast INPUT format.
#
# Aggregated counts on a reference x reporting grid (two ISO-week axes) + full
# identity. Semantically dense (absent observed cell == 0) but stored sparse
# (zeros implied); the as-of boundary (max reporting week) disambiguates
# implied-zero from not-yet-reported. Densification into the ref x delay working
# matrix happens here (reporting_triangle_matrix), bounded by max_delay -- not in
# the constructor, since max_delay is a nowcast parameter.

#' Construct a csfmt_reporting_triangle_v3
#' @param data data.table with identity columns, a reference and a reporting
#'   ISO-week column, and a value column.
#' @param id_cols Identity columns defining a series.
#' @param reference_col,reporting_col ISO-week column names.
#' @param value_col Count column name.
#' @returns A validated `csfmt_reporting_triangle_v3` (a data.table with the
#'   as-of boundary and column roles stored as attributes).
#' @export
csfmt_reporting_triangle_v3 <- function(data, id_cols,
                                        reference_col = "isoyearweek_reference",
                                        reporting_col = "isoyearweek_reporting",
                                        value_col = "numerator") {
  stopifnot(data.table::is.data.table(data),
            all(id_cols %in% names(data)),
            all(c(reference_col, reporting_col, value_col) %in% names(data)))
  d <- data.table::copy(data)
  # NA-safe: a missing reference/reporting week is not a "reporting before
  # reference" violation (it just carries no delay info); only flag genuine
  # negative-delay rows. Callers are responsible for cleaning NA weeks.
  if (any(d[[reporting_col]] < d[[reference_col]], na.rm = TRUE))
    stop("reporting week is before reference week")
  if (any(d[[value_col]] < 0, na.rm = TRUE))
    stop("negative counts in the reporting triangle")

  set_time_series_id(d, id_cols)
  data.table::setattr(d, "id_cols", id_cols)
  data.table::setattr(d, "as_of", max(d[[reporting_col]]))
  data.table::setattr(d, "reference_col", reference_col)
  data.table::setattr(d, "reporting_col", reporting_col)
  data.table::setattr(d, "value_col", value_col)
  data.table::setattr(d, "class", unique(c("csfmt_reporting_triangle_v3", class(d))))
  d[]
}

#' Densify a reporting triangle into per-series reference x delay count matrices
#' @param triangle A `csfmt_reporting_triangle_v3`.
#' @param max_delay Number of delay columns (delay 0 .. max_delay-1, in weeks).
#' @param value_col Which value column to reshape (default the triangle's
#'   `value_col`; pass a denominator column to reshape that instead).
#' @returns Named list (by time_series_id) of `list(reference, mat)`, where `mat`
#'   is a reference x delay count matrix (zeros filled within the observed region).
#' @export
reporting_triangle_matrix <- function(triangle, max_delay,
                                      value_col = attr(triangle, "value_col")) {
  stopifnot(inherits(triangle, "csfmt_reporting_triangle_v3"))
  ref_col <- attr(triangle, "reference_col")
  rep_col <- attr(triangle, "reporting_col")
  val_col <- value_col

  d <- data.table::as.data.table(triangle)
  d[, .ref := get(ref_col)]
  d[, .delay := round(as.numeric(
    cstime::isoyearweek_to_last_date(get(rep_col)) -
      cstime::isoyearweek_to_last_date(get(ref_col))) / 7)]
  d <- d[.delay >= 0 & .delay < max_delay]

  all_weeks  <- cstime::dates_by_isoyearweek$isoyearweek
  delay_cols <- as.character(0:(max_delay - 1))

  out <- list()
  for (tsid in unique(d$time_series_id)) {
    ds <- d[time_series_id == tsid]
    m <- data.table::dcast.data.table(ds, .ref ~ .delay, value.var = val_col,
                                      fun.aggregate = sum, fill = 0)
    for (k in delay_cols) if (!k %in% names(m)) m[, (k) := 0]   # complete delay axis

    # complete the reference axis: contiguous weeks min..max (fills interior gaps
    # and zero-case weeks), so the nowcast truncation works on contiguous rows
    i1 <- match(min(m$.ref), all_weeks); i2 <- match(max(m$.ref), all_weeks)
    full <- data.table::data.table(.ref = all_weeks[i1:i2])
    m <- m[full, on = ".ref"]
    for (k in delay_cols) m[is.na(get(k)), (k) := 0]

    data.table::setcolorder(m, c(".ref", delay_cols))
    out[[tsid]] <- list(reference = m$.ref,
                        mat = as.matrix(m[, delay_cols, with = FALSE]))
  }
  out
}
