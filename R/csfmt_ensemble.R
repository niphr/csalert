# csfmt_ensemble_v3: the working format for draw-parallel surveillance analysis.
#
# An S3 list with two slots:
#   $data  - a data.table, one row per (series x time), the canonical front
#   $draws - named list of [nrow(data) x n_draws] matrices (one per measure),
#            rows aligned 1:1 with $data; NULL/empty until nowcast populates it
#
# Invariants enforced by the constructor (see design doc):
#   - time_series_id    : content hash of the identity columns (stable across
#                         objects/subsets, unlike a positional integer)
#   - time_series_label : readable composite of the identity columns
#   - time_series_internal_id : dense 1..n within each series, in time order
#   - $data sorted by (time_series_id, time_series_internal_id), keyed
#   - every draw matrix has nrow == nrow($data)
#
# Matrices are top-level slots, never cells in $data -- they stay bare and
# vectorisable. The draw axis (matrix columns) is anonymous; the measure name
# (the list key) carries the semantics via the naming grammar.

#' Assign content-hash time_series_id (+ readable label) by reference
#' @param d data.table.
#' @param id_cols Character vector of identity columns defining a series.
#' @param sep Separator for the canonical key (default unit-separator).
#' @returns `d`, modified by reference (invisibly).
#' @family ensemble format functions
#' @seealso Neither package vignette covers this function. It is called for you by
#'   \code{\link{csfmt_ensemble_v3}} and \code{\link{csfmt_reporting_triangle_v3}};
#'   call it directly only when you are keying a data.table those constructors
#'   never see.
#' @examples
#' d <- data.table::data.table(
#'   location_code = c("nation", "nation", "county03"),
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-01"),
#'   numerator = c(10, 12, 4)
#' )
#' set_time_series_id(d, id_cols = c("location_code", "age"))
#'
#' # the two nation rows share one content hash; the county row gets its own
#' d[]
#' @export
set_time_series_id <- function(d, id_cols, sep = "") {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_id <- time_series_label <- NULL
  stopifnot(data.table::is.data.table(d), all(id_cols %in% names(d)))
  i.time_series_id <- i.time_series_label <- NULL
  u <- unique(d[, id_cols, with = FALSE])
  key <- u[, do.call(paste, c(.SD, sep = sep)), .SDcols = id_cols]
  u[, time_series_label := key]
  u[,
    time_series_id := vapply(
      key,
      function(k) digest::digest(k, algo = "xxhash64"),
      character(1)
    )
  ]
  d[
    u,
    on = id_cols,
    `:=`(
      time_series_id = i.time_series_id,
      time_series_label = i.time_series_label
    )
  ]
  invisible(d)
}

#' Construct a csfmt_ensemble_v3
#' @param data data.table with the identity columns and `time_col`.
#' @param id_cols Character vector of identity columns defining a series.
#' @param time_col Time-ordering column (default "isoyearweek").
#' @param draws Optional named list of `[nrow(data) x n_draws]` matrices, given in
#'   `data`'s input row order (they are reordered to match the canonical sort).
#' @returns A `csfmt_ensemble_v3`.
#' @family ensemble format functions
#' @seealso \code{vignette("pipeline", package = "csalert")} is built on this
#'   format: its nowcast engine produces one and \code{\link{ens_collapse}}
#'   reduces it. The vignette never calls this constructor directly, because the
#'   engines build the ensemble for you. Call it yourself only when you already
#'   hold draws from somewhere else.
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' set.seed(1)
#' ens <- csfmt_ensemble_v3(
#'   d,
#'   id_cols = c("location_code", "age"),
#'   draws = list(numerator_nowcasted = matrix(rpois(3 * 100, 20), nrow = 3))
#' )
#' ens
#'
#' # $data carries the identity + the canonical sort keys. The trailing []
#' # forces the print: data.table suppresses the first auto-print of a table
#' # that was last modified by reference, which the constructor does.
#' ens$data[]
#'
#' # $draws holds one [weeks x draws] matrix per measure
#' dim(ens$draws$numerator_nowcasted)
#' @export
csfmt_ensemble_v3 <- function(
  data,
  id_cols,
  time_col = "isoyearweek",
  draws = list()
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_internal_id <- NULL
  stopifnot(
    data.table::is.data.table(data),
    all(id_cols %in% names(data)),
    time_col %in% names(data)
  )
  time_series_id <- .orig_row <- NULL

  d <- data.table::copy(data)
  d[, .orig_row := .I]
  set_time_series_id(d, id_cols)
  data.table::setorderv(d, c("time_series_id", time_col))
  perm <- d$.orig_row
  d[, .orig_row := NULL]
  d[, time_series_internal_id := seq_len(.N), by = time_series_id]
  data.table::setkeyv(d, c("time_series_id", "time_series_internal_id"))

  n <- nrow(d)
  if (length(draws)) {
    for (m in names(draws)) {
      if (!is.matrix(draws[[m]]) || nrow(draws[[m]]) != n) {
        stop(sprintf("draws[['%s']] must be a matrix with %d rows", m, n))
      }
    }
    draws <- lapply(draws, function(M) {
      lv <- attr(M, "levels")
      R <- M[perm, , drop = FALSE]
      if (!is.null(lv)) {
        attr(R, "levels") <- lv
      }
      R
    })
  }

  validate_ensemble(structure(
    list(data = d, draws = draws),
    class = "csfmt_ensemble_v3"
  ))
}

#' Check a csfmt_ensemble_v3's structural shape
#'
#' Checks the shape of an ensemble, and only the shape. It verifies the class,
#' that `$data` is a data.table and `$draws` a list, that `$data` has the
#' `time_series_id` and `time_series_internal_id` columns, and that every entry of
#' `$draws` is a matrix with one row per row of `$data`.
#'
#' @section What it does NOT check:
#' The constructor [csfmt_ensemble_v3] establishes more than this function
#' verifies. It does NOT check the sort order or the key. It also does NOT check:
#' \itemize{
#'   \item that `time_series_internal_id` is a dense 1..n within each series;
#'   \item that `time_series_label` is present;
#'   \item that a draw matrix's rows still correspond to the same weeks as
#'     `$data`.
#' }
#' Only the row COUNT is compared, so permuting the
#' rows of `$data` or of a draw matrix passes.
#'
#' So this is not a safety net for hand-edited objects. If you have edited `$data`
#' or `$draws` yourself, rebuild with [csfmt_ensemble_v3] rather than relying on
#' this check.
#' @param ens A `csfmt_ensemble_v3`.
#' @returns `ens` invisibly; errors on a violation of the shape checks above.
#' @family ensemble format functions
#' @seealso Neither package vignette covers this function. [csfmt_ensemble_v3] and
#'   every ensemble stage call it on the way out, so you rarely call it yourself.
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' ens <- csfmt_ensemble_v3(
#'   d,
#'   id_cols = c("location_code", "age"),
#'   draws = list(numerator_nowcasted = matrix(1:12, nrow = 3))
#' )
#'
#' # returns invisibly when the shape checks pass
#' validate_ensemble(ens)
#'
#' # a draw matrix with the wrong number of rows is caught
#' bad <- ens
#' bad$draws$numerator_nowcasted <- matrix(1, nrow = 2, ncol = 4)
#' try(validate_ensemble(bad))
#'
#' # but a draw matrix whose rows have been PERMUTED has the right count, so it
#' # passes -- the row-to-week correspondence is not checked
#' scrambled <- ens
#' scrambled$draws$numerator_nowcasted <-
#'   ens$draws$numerator_nowcasted[c(2, 3, 1), , drop = FALSE]
#' validate_ensemble(scrambled)
#' "passed, although the draws no longer line up with $data"
#' @export
validate_ensemble <- function(ens) {
  stopifnot(
    inherits(ens, "csfmt_ensemble_v3"),
    data.table::is.data.table(ens$data),
    is.list(ens$draws)
  )
  need <- c("time_series_id", "time_series_internal_id")
  if (!all(need %in% names(ens$data))) {
    stop(
      "ensemble $data missing ",
      paste(setdiff(need, names(ens$data)), collapse = ", ")
    )
  }
  n <- nrow(ens$data)
  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    if (!is.matrix(M)) {
      stop(sprintf("draws[['%s']] is not a matrix", m))
    }
    if (nrow(M) != n) {
      stop(sprintf(
        "draws[['%s']] has %d rows; expected %d (nrow($data))",
        m,
        nrow(M),
        n
      ))
    }
  }
  invisible(ens)
}

#' Print a `csfmt_ensemble_v3`
#'
#' Compact one-line summary: number of rows, number of time series, and the names
#' of the per-measure draw matrices.
#' @param x A `csfmt_ensemble_v3`.
#' @param ... Ignored (for S3 consistency).
#' @returns `x`, invisibly.
#' @family ensemble format functions
#' @seealso \code{vignette("pipeline", package = "csalert")}, which prints an
#'   ensemble with this method right after the nowcast step.
#' @export
print.csfmt_ensemble_v3 <- function(x, ...) {
  cat(sprintf(
    "<csfmt_ensemble_v3> %d rows | %d series | draws: %s\n",
    nrow(x$data),
    data.table::uniqueN(x$data$time_series_id),
    if (length(x$draws)) paste(names(x$draws), collapse = ", ") else "none"
  ))
  invisible(x)
}
