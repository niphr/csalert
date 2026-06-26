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
#' @export
set_time_series_id <- function(d, id_cols, sep = "") {
  stopifnot(data.table::is.data.table(d), all(id_cols %in% names(d)))
  i.time_series_id <- i.time_series_label <- NULL
  u <- unique(d[, id_cols, with = FALSE])
  key <- u[, do.call(paste, c(.SD, sep = sep)), .SDcols = id_cols]
  u[, time_series_label := key]
  u[, time_series_id := vapply(key, function(k) digest::digest(k, algo = "xxhash64"),
                               character(1))]
  d[u, on = id_cols, `:=`(time_series_id = i.time_series_id,
                          time_series_label = i.time_series_label)]
  invisible(d)
}

#' Construct a csfmt_ensemble_v3
#' @param data data.table with the identity columns and `time_col`.
#' @param id_cols Character vector of identity columns defining a series.
#' @param time_col Time-ordering column (default "isoyearweek").
#' @param draws Optional named list of `[nrow(data) x n_draws]` matrices, given in
#'   `data`'s input row order (they are reordered to match the canonical sort).
#' @returns A `csfmt_ensemble_v3`.
#' @export
csfmt_ensemble_v3 <- function(data, id_cols, time_col = "isoyearweek", draws = list()) {
  stopifnot(data.table::is.data.table(data),
            all(id_cols %in% names(data)),
            time_col %in% names(data))
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
      if (!is.matrix(draws[[m]]) || nrow(draws[[m]]) != n)
        stop(sprintf("draws[['%s']] must be a matrix with %d rows", m, n))
    }
    draws <- lapply(draws, function(M) {
      lv <- attr(M, "levels"); R <- M[perm, , drop = FALSE]
      if (!is.null(lv)) attr(R, "levels") <- lv
      R
    })
  }

  validate_ensemble(structure(list(data = d, draws = draws), class = "csfmt_ensemble_v3"))
}

#' Validate a csfmt_ensemble_v3's invariants
#' @param ens A `csfmt_ensemble_v3`.
#' @returns `ens` invisibly; errors on violation.
#' @export
validate_ensemble <- function(ens) {
  stopifnot(inherits(ens, "csfmt_ensemble_v3"),
            data.table::is.data.table(ens$data),
            is.list(ens$draws))
  need <- c("time_series_id", "time_series_internal_id")
  if (!all(need %in% names(ens$data)))
    stop("ensemble $data missing ", paste(setdiff(need, names(ens$data)), collapse = ", "))
  n <- nrow(ens$data)
  for (m in names(ens$draws)) {
    M <- ens$draws[[m]]
    if (!is.matrix(M)) stop(sprintf("draws[['%s']] is not a matrix", m))
    if (nrow(M) != n)
      stop(sprintf("draws[['%s']] has %d rows; expected %d (nrow($data))", m, nrow(M), n))
  }
  invisible(ens)
}

#' @export
print.csfmt_ensemble_v3 <- function(x, ...) {
  cat(sprintf("<csfmt_ensemble_v3> %d rows | %d series | draws: %s\n",
              nrow(x$data),
              data.table::uniqueN(x$data$time_series_id),
              if (length(x$draws)) paste(names(x$draws), collapse = ", ") else "none"))
  invisible(x)
}
