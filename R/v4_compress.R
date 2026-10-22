# The two states of a csfmt_ensemble_v4. A full ensemble holds its draws in
# memory. A compressed ensemble holds, for each base measure, a point value
# and 9 percentiles in $data, and rebuilds the draws from them on demand.

# The seed of the rebuild.
.V4_REBUILD_SEED <- 4L

#' Compress a csfmt_ensemble_v4 into a table to store
#'
#' @description
#' Returns `$data` of `x` as a data.table, with the median and 9 percentiles
#' of each base measure in place of its draws. [as_ensemble_v4()] turns the
#' table back into an ensemble.
#'
#' @details
#' A base measure is a draw matrix whose name does not end in a reserved
#' suffix, such as `_trend_beta1` or `_hlm`. Each base measure `<m>` becomes
#' these columns:
#' - `<m>`: the median of the draws.
#' - `<m>_q02x5` to `<m>_q97x5`: the draws at the 9 percentiles 2.5, 5, 10,
#'   25, 50, 75, 90, 95 and 97.5.
#'
#' The percentiles are `NA` in a row where every draw that is not `NA` has the
#' same value. A row with one draw, as from [nowcast_passthrough_v4()], is
#' such a row. The table does not hold the derived draw matrices. The columns
#' that the steps wrote to `$data` already summarise them.
#'
#' The function draws no random numbers.
#' @param x A `csfmt_ensemble_v4`, full or compressed. Each column of `$data`
#'   MUST be an atomic vector that is not a factor.
#' @returns A data.table with the columns of `x$data` and the columns of each
#'   base measure. Each column name MUST be at most 63 bytes, and the function
#'   stops with an error when one is not.
#' @family v4 functions
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   isoyearweek = sprintf("2023-%02d", 1:10)
#' )
#' set.seed(1)
#' ens <- csfmt_ensemble_v4(
#'   d,
#'   id_cols = "location_code",
#'   draws = list(cases = matrix(rpois(10 * 200, 20), nrow = 10))
#' )
#' stored <- ens_compress_v4(ens)
#' stored[, .(isoyearweek, cases, cases_q02x5, cases_q97x5)]
#' @export
ens_compress_v4 <- function(x) {
  .v4_validate_ensemble(x)
  bad <- vapply(
    x$data,
    function(v) {
      return(is.list(v) || is.matrix(v) || is.factor(v))
    },
    logical(1)
  )
  if (any(bad)) {
    stop(
      "$data has list, matrix or factor columns, which a table cannot ",
      "store: ",
      paste(names(x$data)[bad], collapse = ", "),
      call. = FALSE
    )
  }
  base <- names(x$draws)[!.v4_is_derived(names(x$draws))]
  new <- unlist(lapply(base, .v4_summary_names), use.names = FALSE)
  .v4_check_names(unique(c(names(x$data), new)))

  d <- data.table::copy(x$data)
  for (m in base) {
    .v4_summary_into(d, m, x$draws[[m]])
  }
  return(d)
}

#' Rebuild a csfmt_ensemble_v4 from a stored table
#'
#' @description
#' Turns a table from [ens_compress_v4()] into a compressed
#' `csfmt_ensemble_v4`. The v4 steps take it as they take a full ensemble, and
#' rebuild the draws of each base measure that they read.
#'
#' @details
#' A base measure is a column `<m>` that has the 9 percentile columns
#' `<m>_q02x5` to `<m>_q97x5`, where `<m>` does not end in a reserved suffix.
#' The table holds no other metadata, so a table with every attribute removed
#' gives the same ensemble.
#'
#' The rebuild draws one u from U(0, 1) per row and draw for each base
#' measure. It then puts back the random-number state of the caller. The seed
#' of a measure comes from its name and seed 4, so it does not depend on the
#' order of the rebuilds. Two measures, and two weeks of a series, get
#' independent u, as the numerator and the denominator of [nowcast_ecdf_v4()]
#' are independent. The value of a draw is u through the quantile function of
#' the row. That function
#' interpolates linearly between the 9 stored percentiles, and it is flat
#' below 2.5% and above 97.5%. A row with `NA` percentiles gets its point
#' value in every draw.
#'
#' A rate rebuilt from its own percentiles keeps the stored distribution of
#' the rate. A rate added again from its rebuilt parts with [ens_add_rate_v4()]
#' is the ratio of independent draws, as in a full ensemble from
#' [nowcast_ecdf_v4()].
#' @param d The table from [ens_compress_v4()], as a data.table or a
#'   data.frame. A DBI read returns a data.frame. The function converts a copy,
#'   so the object of the caller does not change.
#' @param id_cols The identity columns that define one series.
#' @param time_col The column that orders time within a series.
#' @param n_sim The number of draws in each rebuilt draw matrix.
#' @returns A `csfmt_ensemble_v4` with `state` `"compressed"`. Its `$draws` is
#'   empty, and it holds only the draw matrices that the steps add.
#' @family v4 functions
#' @examples
#' d <- data.table::data.table(
#'   location_code = "nation",
#'   isoyearweek = sprintf("2023-%02d", 1:10)
#' )
#' set.seed(1)
#' ens <- csfmt_ensemble_v4(
#'   d,
#'   id_cols = "location_code",
#'   draws = list(cases = matrix(rpois(10 * 200, 20 * exp(0.1 * 1:10)), 10))
#' )
#' stored <- ens_compress_v4(ens)
#' back <- as_ensemble_v4(stored, id_cols = "location_code")
#' back
#' back <- short_term_trend_v4(back, measure = "cases", width = 5, seed = 4)
#' back$data[, .(isoyearweek, cases, cases_trend_pinc)]
#' @export
as_ensemble_v4 <- function(
  d,
  id_cols,
  time_col = "isoyearweek",
  n_sim = 1000L
) {
  return(.v4_as_ensemble(d, id_cols, time_col, n_sim))
}

# The work of as_ensemble_v4().
.v4_as_ensemble <- function(d, id_cols, time_col, n_sim) {
  if (!is.data.frame(d)) {
    stop("`d` must be a data.frame or a data.table", call. = FALSE)
  }
  # A copy, so that the object of the caller does not change.
  d <- data.table::as.data.table(d)
  if (!.v4_is_whole_number(n_sim) || n_sim < 1) {
    stop("`n_sim` must be one whole number of at least 1", call. = FALSE)
  }
  stored <- .v4_stored_measures(names(d))
  cols <- unlist(lapply(stored, .v4_summary_names), use.names = FALSE)
  numeric_col <- vapply(
    cols,
    function(v) {
      return(is.numeric(d[[v]]))
    },
    logical(1)
  )
  if (!all(numeric_col)) {
    stop(
      "the stored measure columns must be numeric: ",
      paste(cols[!numeric_col], collapse = ", "),
      call. = FALSE
    )
  }
  x <- csfmt_ensemble_v4(d, id_cols = id_cols, time_col = time_col)
  x$state <- "compressed"
  x$n_sim <- as.integer(n_sim)
  x$cache <- new.env(parent = emptyenv())
  return(.v4_validate_ensemble(x))
}

# The draws of `measure` in the ensemble `x`. A draw matrix in $draws is
# returned as it is. In a compressed ensemble, a stored base measure that is
# not in $draws is rebuilt from its percentiles. Every v4 step reads its draws
# through this function, so that it works in both states.
.v4_draws <- function(x, measure) {
  if (measure %in% names(x$draws)) {
    return(x$draws[[measure]])
  }
  if (!measure %in% .v4_measures(x)) {
    stop("`measure` must name one matrix in $draws", call. = FALSE)
  }
  u <- .v4_rebuild_u(x, measure)
  q <- as.matrix(x$data[, .v4_summary_names(measure)[-1], with = FALSE])
  return(.v4_quantile_map(x$data[[measure]], q, u))
}

# The names of the measures of `x`: the draw matrices in $draws and, in a
# compressed ensemble, the base measures stored in $data.
.v4_measures <- function(x) {
  out <- names(x$draws)
  if (identical(x$state, "compressed")) {
    out <- union(out, .v4_stored_measures(names(x$data)))
  }
  return(out)
}

# The dimensions of the draw matrix of `measure`, with no rebuild.
.v4_draw_dim <- function(x, measure) {
  if (measure %in% names(x$draws)) {
    return(dim(x$draws[[measure]]))
  }
  return(c(nrow(x$data), x$n_sim))
}

# TRUE for each name that ends in a reserved suffix.
.v4_is_derived <- function(x) {
  pattern <- paste0("(", paste(.V4_RESERVED_SUFFIXES, collapse = "|"), ")$")
  return(grepl(pattern, x))
}

# The point column and the 9 percentile columns of the base measure `m`.
.v4_summary_names <- function(m) {
  return(c(m, paste0(m, "_", .v4_q_label(.V4_PROBS))))
}

# The base measures stored in a table with the column names `cols`: each
# column that has its 9 percentile columns and no reserved suffix.
.v4_stored_measures <- function(cols) {
  full <- vapply(
    cols,
    function(m) {
      return(all(.v4_summary_names(m)[-1] %in% cols))
    },
    logical(1),
    USE.NAMES = FALSE
  )
  return(cols[full & !.v4_is_derived(cols)])
}

# Write the median of the draw matrix `M` to the column `m` of `d`, and its 9
# percentiles to the columns `<m>_q02x5` to `<m>_q97x5`, by reference. The
# percentiles are NA in a row where every draw that is not NA is equal.
.v4_summary_into <- function(d, m, M) {
  n <- nrow(M)
  med <- matrixStats::rowMedians(M, na.rm = TRUE)
  med[is.nan(med)] <- NA_real_
  q <- matrixStats::rowQuantiles(M, probs = .V4_PROBS, na.rm = TRUE)
  q <- matrix(as.numeric(q), n, length(.V4_PROBS))
  r <- suppressWarnings(matrixStats::rowRanges(M, na.rm = TRUE))
  q[!(r[, 2] > r[, 1]), ] <- NA_real_
  nm <- .v4_summary_names(m)
  d[, (nm[1]) := as.numeric(med)]
  d[, (nm[-1]) := data.table::as.data.table(q)]
  return(invisible(d))
}

# The u matrix of the rebuild of `measure` in `x`: one row per row of $data
# and one column per draw. It is drawn once per measure and kept in x$cache.
# Its seed comes from the name of the measure and seed 4, so it does not
# depend on which measure is rebuilt first. Each measure has its own u, so
# the draws of a numerator and its denominator are independent, as they are
# in nowcast_ecdf_v4().
.v4_rebuild_u <- function(x, measure) {
  if (is.null(x$cache$u)) {
    x$cache$u <- list()
  }
  if (is.null(x$cache$u[[measure]])) {
    x$cache$u[[measure]] <- .v4_with_seed(
      .v4_rebuild_seed(measure),
      .v4_draw_u(x$data, x$time_col, x$n_sim)
    )
  }
  return(x$cache$u[[measure]])
}

# The seed of the rebuild of `measure`: a whole number from its name and
# seed 4.
.v4_rebuild_seed <- function(measure) {
  return(digest::digest2int(measure, seed = .V4_REBUILD_SEED))
}

# Draw one u per row and draw, in a fixed order: the series sorted by
# time_series_id, then the weeks. The caller sets the seed.
.v4_draw_u <- function(data, time_col, n_sim) {
  sid <- data$time_series_id
  n <- length(sid)
  o <- order(sid, data[[time_col]], method = "radix")
  u <- matrix(NA_real_, n, n_sim)
  u[o, ] <- stats::runif(n * n_sim)
  return(u)
}

# Map each u through the quantile function of its row. `q` holds the 9
# percentiles of each row at .V4_PROBS. The function interpolates linearly
# between them, and is flat below the first and above the last. A row with an
# NA percentile gets `point` in every draw.
.v4_quantile_map <- function(point, q, u) {
  n <- nrow(u)
  p <- .V4_PROBS
  uc <- pmin(pmax(u, p[1]), p[length(p)])
  j <- findInterval(uc, p, all.inside = TRUE)
  row <- rep(seq_len(n), ncol(u))
  lo <- q[cbind(row, j)]
  hi <- q[cbind(row, j + 1L)]
  w <- (uc - p[j]) / (p[j + 1L] - p[j])
  # This form gives the stored value exactly at w = 0 and at w = 1.
  out <- (1 - w) * lo + w * hi
  out <- matrix(out, n, ncol(u))
  na_q <- rowSums(is.na(q)) > 0
  out[na_q, ] <- as.numeric(point[na_q])
  return(out)
}
