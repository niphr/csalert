# csfmt_ensemble_v4: the working format of the v4 methods. A list with the
# slots `data`, `draws`, `id_cols`, `time_col` and `state`. The slots are list
# elements, so they survive a subset or a copy that drops attributes.

.V4_ENSEMBLE_STATES <- "full"

#' Build a csfmt_ensemble_v4
#'
#' Builds the ensemble that the v4 methods take and return. It holds one row
#' per series and week in `$data`, and one draw matrix per measure in `$draws`.
#'
#' The constructor copies `data` and adds `time_series_id` and
#' `time_series_label`. It sorts the rows by series and `time_col`, adds
#' `time_series_internal_id`, `1..n` within each series, and puts the draw rows
#' in the same order. The names of the columns and of the draw matrices MUST be
#' at most 63 bytes, and MUST differ in their first 63 bytes.
#' @param data A data.table with the identity columns and `time_col`.
#' @param id_cols The identity columns that define one series.
#' @param time_col The column that orders time within a series.
#' @param draws A named list of matrices, one per measure, with `nrow(data)`
#'   rows in the row order of `data`.
#' @returns A `csfmt_ensemble_v4`: a list with `data`, `draws`, `id_cols`,
#'   `time_col` and `state`. The `state` is `"full"`, which means that `$draws`
#'   holds the draws.
#' @family v4 functions
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   age = "total",
#'   isoyearweek = c("2023-01", "2023-02", "2023-03")
#' )
#' set.seed(1)
#' ens <- csfmt_ensemble_v4(
#'   d,
#'   id_cols = c("location_code", "age"),
#'   draws = list(numerator = matrix(rpois(3 * 100, 20), nrow = 3))
#' )
#' ens
#' ens$state
#' @export
csfmt_ensemble_v4 <- function(
  data,
  id_cols,
  time_col = "isoyearweek",
  draws = list()
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_id <- time_series_internal_id <- .orig_row <- NULL
  stopifnot(
    data.table::is.data.table(data),
    is.character(id_cols),
    all(id_cols %in% names(data)),
    is.character(time_col),
    length(time_col) == 1L,
    time_col %in% names(data),
    is.list(draws)
  )
  d <- data.table::copy(data)
  d[, .orig_row := .I]
  .v4_set_time_series_id(d, id_cols)
  data.table::setorderv(d, c("time_series_id", time_col))
  perm <- d$.orig_row
  d[, .orig_row := NULL]
  d[, time_series_internal_id := seq_len(.N), by = time_series_id]
  data.table::setkeyv(d, c("time_series_id", "time_series_internal_id"))

  n <- nrow(d)
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

  return(.v4_validate_ensemble(structure(
    list(
      data = d,
      draws = draws,
      id_cols = id_cols,
      time_col = time_col,
      state = "full"
    ),
    class = "csfmt_ensemble_v4"
  )))
}

# Check the shape of a csfmt_ensemble_v4, and return it invisibly. It checks
# the slots, the names, and the row count of each draw matrix. It does not
# check the row order.
.v4_validate_ensemble <- function(ens) {
  stopifnot(
    inherits(ens, "csfmt_ensemble_v4"),
    data.table::is.data.table(ens$data),
    is.list(ens$draws),
    is.character(ens$id_cols),
    is.character(ens$time_col),
    length(ens$time_col) == 1L
  )
  if (!identical(ens$state, .V4_ENSEMBLE_STATES)) {
    stop(
      "ensemble $state must be one of: ",
      paste(.V4_ENSEMBLE_STATES, collapse = ", "),
      call. = FALSE
    )
  }
  need <- c(
    ens$id_cols,
    ens$time_col,
    "time_series_id",
    "time_series_internal_id"
  )
  if (!all(need %in% names(ens$data))) {
    stop(
      "ensemble $data misses ",
      paste(setdiff(need, names(ens$data)), collapse = ", "),
      call. = FALSE
    )
  }
  if (length(ens$draws) && is.null(names(ens$draws))) {
    stop("ensemble $draws must be a named list", call. = FALSE)
  }
  .v4_check_names(c(names(ens$data), names(ens$draws)))
  n <- nrow(ens$data)
  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    if (!is.matrix(M) || nrow(M) != n) {
      stop(
        sprintf("draws[['%s']] must be a matrix with %d rows", m, n),
        call. = FALSE
      )
    }
  }
  return(invisible(ens))
}

#' Print a csfmt_ensemble_v4
#'
#' Prints one line: the state, the number of rows and of series, and the names
#' of the draw matrices.
#' @param x The `csfmt_ensemble_v4` to print.
#' @param ... Not used. The `print()` generic has it.
#' @returns `x`, invisibly.
#' @family v4 functions
#' @export
print.csfmt_ensemble_v4 <- function(x, ...) {
  draws <- "none"
  if (length(x$draws)) {
    draws <- paste(names(x$draws), collapse = ", ")
  }
  cat(sprintf(
    "<csfmt_ensemble_v4> %s | %d rows | %d series | draws: %s\n",
    x$state,
    nrow(x$data),
    data.table::uniqueN(x$data$time_series_id),
    draws
  ))
  return(invisible(x))
}
