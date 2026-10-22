# short_term_trend_v4: the rolling quasi-Poisson trend of every draw of a
# csfmt_ensemble_v4. It fits the windows with .v4_rolling_qp_offset() and
# applies the window rules of the v1 method.

# The largest number of cells in one kernel call. The draws go to the kernel
# in chunks of this size, so that the memory of one call stays bounded.
.V4_TREND_CHUNK_CELLS <- 1e6

#' Fit the short-term trend of every draw of a csfmt_ensemble_v4
#'
#' @description
#' Fits a rolling quasi-Poisson regression of `measure` on the week index in
#' every draw. With `denominator`, the fit is the rate model
#' `measure ~ t + offset(log(denominator))`.
#'
#' @details
#' The window of a week holds that week and the `width - 1` weeks before it.
#' The time `t` is the week index, so the slope is a change of the log mean
#' per week. The fit is that of [stats::glm()] with the quasi-Poisson family,
#' and the dispersion has no floor.
#'
#' Each series MUST have one row per ISO week, from its first week to its
#' last, as the output of [nowcast_passthrough_v4()] has. The function reads
#' the weeks from `x$time_col`. It stops with an error that names the series
#' and the two weeks around the gap when a week is missing or repeated. It
#' also stops when `x$time_col` holds a value that is not an ISO week. A
#' week with no count MUST be a row with `NA`.
#'
#' A row with an `NA` count or denominator leaves the window. A zero
#' denominator becomes 1 before the log, as in the v1 method. The first of
#' these rules that holds for a window, in one draw, decides its values:
#' - **Rule 3.** A window with `NA` rows and fewer than 3 rows left gets `NA`.
#' - **Rule 2.** A window where every count left is 0 gets P(increasing) 0,
#'   and `NA` slope, standard error and growth rate.
#' - **Rule 4.** A window gets `NA` when its fit does not converge, has a
#'   non-finite value, or has separated counts. The fit needs 3 rows, so a
#'   window of width 2 with a count above 0 also gets `NA`.
#' - Every other window gets the slope and standard error of its fit.
#'
#' The first `width - 1` weeks of each series have no window and get `NA`.
#'
#' P(increasing) is the mean over draws `j` of `pt(beta1_j / se_j, df_j)`.
#' Here `df_j` is the number of rows left in the window minus 2. A draw with
#' `NA` leaves the mean, and the mean of no draws is `NA`.
#'
#' The growth rate is `100 * (exp(b_j) - 1)` percent per week, with
#' `b_j = beta1_j + se_j * t_j`. Each draw gets one `t_j` from the t
#' distribution with `df_j` degrees of freedom. The percentiles are over the
#' draws. With one draw, the function draws no random number: the percentile
#' `p` is then `100 * (exp(beta1 + se * qt(p, df)) - 1)`.
#'
#' The function sets `seed` itself, and then puts back the random-number state
#' of the caller.
#' @param x The `csfmt_ensemble_v4`, full or compressed.
#' @param measure The name of the draw matrix of counts in `$draws`.
#' @param width The number of weeks in a window, one whole number of at least
#'   2.
#' @param denominator `NULL` for a count, or the name of the draw matrix of the
#'   denominator for a rate.
#' @param name The start of the new names. It MUST NOT end in a reserved
#'   suffix, and each new name MUST be at most 63 bytes.
#' @param seed The seed of the t draws, one whole number.
#' @returns `x` with the new draw matrices `<name>_trend_beta1` and
#'   `<name>_trend_se`, and these new columns in `$data`:
#'   - `<name>_trend_pinc`: P(increasing).
#'   - `<name>_trend_gr`: the median growth rate.
#'   - `<name>_trend_gr_q02x5` to `<name>_trend_gr_q97x5`: the growth rate at
#'     the 9 percentiles 2.5, 5, 10, 25, 50, 75, 90, 95 and 97.5.
#'
#'   A rerun with the same `name` replaces these draw matrices and columns.
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
#' ens <- short_term_trend_v4(ens, measure = "cases", width = 5, seed = 4)
#' ens$data[, .(isoyearweek, cases_trend_pinc, cases_trend_gr)]
#' @export
short_term_trend_v4 <- function(
  x,
  measure,
  width = 3,
  denominator = NULL,
  name = measure,
  seed
) {
  .v4_validate_ensemble(x)
  .v4_trend_check_args(x, measure, width, denominator)
  .v4_check_measure_names(name)
  nm <- .v4_trend_names(name)
  .v4_check_names(unlist(nm, use.names = FALSE))
  .v4_check_weeks(x)

  fit <- .v4_trend_fit(
    Y = .v4_draws(x, measure),
    D = if (!is.null(denominator)) .v4_draws(x, denominator),
    series = x$data$time_series_id,
    pos = x$data$time_series_internal_id,
    width = width
  )
  pinc <- .v4_trend_pinc(fit)
  gr <- .v4_with_seed(seed, .v4_trend_growth(fit))

  d <- data.table::copy(x$data)
  d[, (nm$pinc) := pinc]
  d[, (nm$gr) := gr$median]
  d[, (nm$gr_q) := data.table::as.data.table(gr$q)]
  x$data <- d
  x$draws[[nm$beta1]] <- fit$beta1
  x$draws[[nm$se]] <- fit$se
  .v4_validate_ensemble(x)
  return(x)
}

# Stop unless `measure` and `denominator` name draw matrices of the same
# dimensions, and `width` is one whole number of at least 2.
.v4_trend_check_args <- function(x, measure, width, denominator) {
  given <- c(list(measure), if (!is.null(denominator)) list(denominator))
  named <- vapply(
    given,
    function(m) {
      return(is.character(m) && length(m) == 1L && m %in% .v4_measures(x))
    },
    logical(1)
  )
  if (!all(named)) {
    stop(
      "`measure` and `denominator` must each name one matrix in $draws",
      call. = FALSE
    )
  }
  if (
    !is.null(denominator) &&
      !identical(.v4_draw_dim(x, measure), .v4_draw_dim(x, denominator))
  ) {
    stop(
      "the measure and denominator matrices differ in dimensions",
      call. = FALSE
    )
  }
  if (!.v4_is_whole_number(width) || width < 2) {
    stop("`width` must be one whole number of at least 2", call. = FALSE)
  }
  return(invisible(NULL))
}

# TRUE when `v` is one finite whole number.
.v4_is_whole_number <- function(v) {
  return(is.numeric(v) && length(v) == 1L && is.finite(v) && v == round(v))
}

# The new names of a trend. The caller checks them with .v4_check_names().
.v4_trend_names <- function(name) {
  return(list(
    beta1 = paste0(name, "_trend_beta1"),
    se = paste0(name, "_trend_se"),
    pinc = paste0(name, "_trend_pinc"),
    gr = paste0(name, "_trend_gr"),
    gr_q = paste0(name, "_trend_gr_", .v4_q_label(.V4_PROBS))
  ))
}

# Stop unless every series of `x` has one row per ISO week of `x$time_col`,
# from its first week to its last. The rows are sorted by series and week.
.v4_check_weeks <- function(x) {
  weeks <- x$data[[x$time_col]]
  monday <- .v4_isoyearweek_week_start(weeks)
  if (anyNA(monday)) {
    stop(
      "`",
      x$time_col,
      "` must hold ISO weeks, such as '2023-01'. Not one: '",
      weeks[is.na(monday)][1],
      "'",
      call. = FALSE
    )
  }
  sid <- x$data$time_series_id
  n <- length(sid)
  step <- as.numeric(monday[-1]) - as.numeric(monday[-n])
  bad <- which(sid[-1] == sid[-n] & step != 7)
  if (length(bad)) {
    i <- bad[1]
    ids <- vapply(
      x$id_cols,
      function(col) {
        return(paste0(col, "=", x$data[[col]][i]))
      },
      character(1)
    )
    stop(
      "series ",
      paste(ids, collapse = ", "),
      " is not one row per ISO week: ",
      weeks[i],
      " is followed by ",
      weeks[i + 1],
      ". Add the missing weeks as rows with NA.",
      call. = FALSE
    )
  }
  return(invisible(NULL))
}

# Fit every window of every draw. `Y` and `D` have one row per row of $data,
# and one column per draw. Row `i` is row `pos[i]` of series `series[i]`. The
# result holds 4 matrices like `Y`: `beta1`, `se` and `df` after the window
# rules, and `zero`, which is TRUE where rule 2 holds.
.v4_trend_fit <- function(
  Y,
  D,
  series,
  pos,
  width,
  chunk_cells = .V4_TREND_CHUNK_CELLS
) {
  n <- nrow(Y)
  n_draw <- ncol(Y)
  s <- match(series, unique(series))
  n_series <- max(s, 0L)
  n_len <- max(pos, 0L)
  # The cell of each row in a kernel matrix of n_len rows and one column per
  # series.
  cell <- pos + n_len * (s - 1L)
  log_d <- NULL
  if (!is.null(D)) {
    D[!is.na(D) & D == 0] <- 1
    log_d <- log(D)
  }

  empty <- matrix(NA_real_, n, n_draw)
  out <- list(beta1 = empty, se = empty, df = empty)
  out$zero <- matrix(FALSE, n, n_draw)
  per_chunk <- max(1L, floor(chunk_cells / max(1, n_len * n_series)))
  for (first in seq(1L, n_draw, by = per_chunk)) {
    j <- first:min(n_draw, first + per_chunk - 1L)
    at <- cell + rep((seq_along(j) - 1L) * n_len * n_series, each = n)
    to_kernel <- function(M) {
      K <- matrix(NA_real_, n_len, n_series * length(j))
      K[at] <- M[, j]
      return(K)
    }
    k <- .v4_rolling_qp_offset(
      Y = to_kernel(Y),
      OFF = if (!is.null(log_d)) to_kernel(log_d),
      TT = matrix(as.numeric(seq_len(n_len)), n_len, n_series * length(j)),
      width = width,
      na_rm = TRUE,
      extended = TRUE
    )
    r <- .v4_trend_rules(k, at, width)
    for (v in names(out)) {
      out[[v]][, j] <- r[[v]]
    }
  }
  return(out)
}

# The window rules of the v1 method, at the cells `at` of the kernel output
# `k`. The first rule that holds decides.
.v4_trend_rules <- function(k, at, width) {
  n_used <- k$n_used[at]
  # Rule 3: NA rows, and fewer than 3 rows left.
  too_few <- n_used < width & n_used < .V4_MIN_ROWS
  # Rule 2: every count left is 0.
  zero <- !too_few & k$n_pos[at] == 0
  zero <- zero %in% TRUE
  # Rule 4: no convergence, a non-finite value, or separated counts.
  fitted <- (k$converged[at] & !k$separated[at]) %in% TRUE & !zero
  keep <- function(v) {
    v[!fitted] <- NA_real_
    return(v)
  }
  return(list(
    beta1 = keep(k$beta1[at]),
    se = keep(k$se[at]),
    df = keep(k$df[at]),
    zero = zero
  ))
}

# P(increasing) of each row: the mean over the draws of pt(beta1 / se, df).
# A draw under rule 2 counts 0, and a draw with NA leaves the mean.
.v4_trend_pinc <- function(fit) {
  P <- stats::pt(fit$beta1 / fit$se, fit$df)
  P[fit$zero] <- 0
  pinc <- rowMeans(P, na.rm = TRUE)
  pinc[is.nan(pinc)] <- NA_real_
  return(pinc)
}

# The median growth rate of each row, and its percentiles at .V4_PROBS. With
# one draw they are in closed form. With more draws, each draw gets one t
# draw, so the caller MUST set the seed.
.v4_trend_growth <- function(fit) {
  n <- nrow(fit$beta1)
  if (ncol(fit$beta1) == 1L) {
    b1 <- fit$beta1[, 1]
    se <- fit$se[, 1]
    df <- fit$df[, 1]
    q <- vapply(
      .V4_PROBS,
      function(p) {
        return(100 * (exp(b1 + se * stats::qt(p, df)) - 1))
      },
      numeric(n)
    )
    q <- matrix(q, n, length(.V4_PROBS))
    med <- 100 * (exp(b1 + se * stats::qt(0.5, df)) - 1)
    return(list(median = med, q = q))
  }
  ok <- !is.na(fit$beta1)
  t_draw <- matrix(NA_real_, n, ncol(fit$beta1))
  t_draw[ok] <- stats::rt(sum(ok), fit$df[ok])
  G <- 100 * (exp(fit$beta1 + fit$se * t_draw) - 1)
  q <- matrixStats::rowQuantiles(G, probs = .V4_PROBS, na.rm = TRUE)
  q <- matrix(q, n, length(.V4_PROBS))
  med <- matrixStats::rowMedians(G, na.rm = TRUE)
  # The median of no draws is NaN. It is NA, as the percentiles are.
  med[is.nan(med)] <- NA_real_
  return(list(median = med, q = q))
}
