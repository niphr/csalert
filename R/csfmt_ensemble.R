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

#' Add a content-hash series id to a data.table
#'
#' Adds `time_series_label`, the identity values joined by `sep`, and
#' `time_series_id`, the xxhash64 digest of that label. The id depends only on the
#' identity values, so a series gets the same id in every table.
#'
#' [csfmt_ensemble_v3()] and [csfmt_reporting_triangle_v3()] call this function for
#' you.
#' @param d A data.table. The function changes it by reference.
#' @param id_cols The identity columns that define one series.
#' @param sep The separator in the label. The default is the ASCII unit
#'   separator, `"\037"`.
#' @returns `d`, invisibly.
#' @family ensemble format functions
#' @seealso `vignette("pipeline", package = "csalert")`, which shows the ensemble
#'   format.
#' @examples
#' d <- data.table::data.table(
#'   location_code = c("nation", "nation", "county03"),
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-01"),
#'   numerator = c(10, 12, 4)
#' )
#' set_time_series_id(d, id_cols = c("location_code", "age"))
#'
#' # the two nation rows share one id, and the county row has its own
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
  return(invisible(d))
}

#' Build a csfmt_ensemble_v3
#'
#' Builds the working format of the pipeline. `$data` is a data.table with one
#' row per series and week. `$draws` holds one matrix per measure, with one row
#' per row of `$data` and one column per draw.
#'
#' The constructor copies `data`, adds the ids of [set_time_series_id()], and
#' sorts the rows by series and `time_col`. It adds `time_series_internal_id`,
#' `1..n` within each series, and puts the draw rows in the same order. The
#' nowcast engines call it for you.
#' @param data A data.table with the identity columns and `time_col`.
#' @param id_cols The identity columns that define one series.
#' @param time_col The column that orders time within a series.
#' @param draws A named list of matrices, one per measure, with `nrow(data)` rows
#'   in the row order of `data`.
#' @returns A `csfmt_ensemble_v3`.
#' @family ensemble format functions
#' @seealso `vignette("pipeline", package = "csalert")`, which builds an ensemble
#'   with a nowcast engine.
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
#' # $data holds the identity columns and the sort keys. The trailing [] makes
#' # data.table print a table that was last changed by reference.
#' ens$data[]
#'
#' # $draws holds one matrix per measure, with rows = weeks, columns = draws
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
        stop(
          sprintf("draws[['%s']] must be a matrix with %d rows", m, n),
          call. = FALSE
        )
      }
    }
    draws <- lapply(draws, function(M) {
      lv <- attr(M, "levels")
      R <- M[perm, , drop = FALSE]
      if (!is.null(lv)) {
        attr(R, "levels") <- lv
      }
      return(R)
    })
  }

  return(validate_ensemble(structure(
    list(data = d, draws = draws),
    class = "csfmt_ensemble_v3"
  )))
}

#' Check the shape of a csfmt_ensemble_v3
#'
#' Checks the class, and that `$data` is a data.table with `time_series_id` and
#' `time_series_internal_id`. Checks that each entry of `$draws` is a matrix
#' with one row per row of `$data`. Every ensemble stage calls it.
#' @section What it does NOT check:
#' It does NOT check:
#' * the sort order or the key of `$data`,
#' * that `time_series_internal_id` counts `1..n` in each series,
#' * that `time_series_label` exists.
#'
#' It compares only the number of rows, so a draw
#' matrix with its rows in the wrong order passes. If you edit `$data` or `$draws`
#' yourself, rebuild the object with [csfmt_ensemble_v3()].
#' @param ens The `csfmt_ensemble_v3` to check.
#' @returns `ens`, invisibly. A failed check is an error.
#' @family ensemble format functions
#' @seealso `vignette("pipeline", package = "csalert")`, which shows the ensemble
#'   format.
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
#' # returns invisibly when the checks pass
#' validate_ensemble(ens)
#'
#' # a draw matrix with the wrong number of rows is an error
#' bad <- ens
#' bad$draws$numerator_nowcasted <- matrix(1, nrow = 2, ncol = 4)
#' try(validate_ensemble(bad))
#'
#' # a draw matrix with PERMUTED rows has the right count, so it passes
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
      paste(setdiff(need, names(ens$data)), collapse = ", "),
      call. = FALSE
    )
  }
  n <- nrow(ens$data)
  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    if (!is.matrix(M)) {
      stop(sprintf("draws[['%s']] is not a matrix", m), call. = FALSE)
    }
    if (nrow(M) != n) {
      stop(
        sprintf(
          "draws[['%s']] has %d rows; expected %d (nrow($data))",
          m,
          nrow(M),
          n
        ),
        call. = FALSE
      )
    }
  }
  return(invisible(ens))
}

#' Print a `csfmt_ensemble_v3`
#'
#' Prints one line: the number of rows and of series, and the names of the draw
#' matrices.
#' @param x The `csfmt_ensemble_v3` to print.
#' @param ... Not used, but the `print()` generic has it.
#' @returns `x`, invisibly.
#' @family ensemble format functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 1.
#' @export
print.csfmt_ensemble_v3 <- function(x, ...) {
  cat(sprintf(
    "<csfmt_ensemble_v3> %d rows | %d series | draws: %s\n",
    nrow(x$data),
    data.table::uniqueN(x$data$time_series_id),
    if (length(x$draws)) paste(names(x$draws), collapse = ", ") else "none"
  ))
  return(invisible(x))
}
