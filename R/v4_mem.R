# mem_thresholds_v4: a copy of mem_thresholds_v1.csfmt_ensemble_v3 on the v4
# format. It fits the MEM thresholds of each season from the medians of the
# draws in earlier seasons, and classifies every draw against them.

# The levels of the MEM status, coded 1 to 5.
.V4_MEM_LEVELS <- c("preepidemic", "low", "medium", "high", "veryhigh")

# The thresholds of a fit, in the order of the levels they start.
.V4_MEM_THRESHOLDS <- c("preepidemic", "medium", "high", "veryhigh")

#' Classify the draws of a csfmt_ensemble_v4 into MEM intensity levels
#'
#' @description
#' Fits Moving Epidemic Method (MEM) thresholds for each season from the
#' earlier seasons of the same series, and classifies every draw against them.
#' The method is that of [mem_thresholds_v1()] for a `csfmt_ensemble_v3`, and
#' the values are identical.
#'
#' @details
#' The fit uses the median of the draws of each week. A season is fit only on
#' earlier seasons: those with at least `min_weeks_per_season` weeks, minus
#' `exclude_seasons`, and at most the latest `i.seasons`. The seasons and the
#' season weeks come from the ISO weeks in `x$time_col`.
#'
#' A season gets no thresholds, and `NA` in every draw, in three cases:
#' - it has fewer than `min_seasons` training seasons;
#' - fewer than 2 of them hold a week above 0;
#' - `mem::memmodel()` fails with its default method and with `i.method = 3`.
#'
#' A fit on fewer than `prefer_seasons` seasons is provisional, and a message
#' counts those seasons.
#'
#' The levels, coded 1 to 5, are:
#' 1. `preepidemic`: below the MEM epidemic threshold.
#' 2. `low`: below the 40% intensity threshold.
#' 3. `medium`: below the 90% intensity threshold.
#' 4. `high`: below the 97.5% intensity threshold.
#' 5. `veryhigh`: at or above the 97.5% intensity threshold.
#'
#' The function draws no random numbers. It needs the mem package.
#' The function takes no `...`, so a misspelt argument is an error.
#' @param x The `csfmt_ensemble_v4`, full or compressed.
#' @param measure The name of the draw matrix to classify, a count or a rate.
#'   It MUST NOT end in a reserved suffix.
#' @param min_seasons The fewest training seasons for a fit.
#' @param prefer_seasons A fit on fewer training seasons is provisional.
#' @param i.seasons The most training seasons in one fit, passed to
#'   `mem::memmodel()`.
#' @param min_weeks_per_season The fewest weeks that a training season needs.
#' @param exclude_seasons Seasons to leave out of every training set, written
#'   as `cstime::isoyearweek_to_season_c()` writes them, such as
#'   `"2019/2020"`. An excluded season still gets thresholds, and a message
#'   names the excluded seasons in the data.
#' @returns `x` with the new draw matrix `<measure>_mem`, which holds the level
#'   codes 1 to 5 with a `levels` attribute. It adds these columns to `$data`:
#'   - `<measure>_mem_thr_preepidemic`, `<measure>_mem_thr_medium`,
#'     `<measure>_mem_thr_high` and `<measure>_mem_thr_veryhigh`: the
#'     thresholds of the season of the week.
#'   - `<measure>_mem_n_seasons`: the number of training seasons of the fit.
#'   - `<measure>_mem_thr_postepidemic`: the post-epidemic threshold of the
#'     season, `epidemic.thresholds[2]` of the fit. It classifies no draw.
#'   - `<measure>_mem_season_start` and `<measure>_mem_season_weeks`, both
#'     integer: `mean.start` and `mean.length` of the fit. The start is the
#'     rounded mean position of the first epidemic week among the season weeks
#'     of the fit, counted from 1. The length is the rounded mean epidemic
#'     length in weeks.
#'   - `<measure>_mem_prob_preepidemic` to `<measure>_mem_prob_veryhigh`: the
#'     share of the draws at each level, which is `NA` when every draw is
#'     `NA`.
#'
#'   Each threshold and each fit field repeats on every week of the season,
#'   and is `NA` in a season with no fit.
#'
#'   The shares give every ordinal percentile of the level codes, so the step
#'   writes no percentile column.
#'
#'   Each new name MUST be at most 63 bytes. A rerun on the same `measure`
#'   replaces the draw matrix and the columns. The input `x` does not change.
#' @family v4 functions
#' @examples
#' # MEM needs earlier seasons, so this series spans four: 212 weeks with a
#' # winter peak in each.
#' if (requireNamespace("mem", quietly = TRUE)) {
#'   w <- cstime::dates_by_isoyearweek$isoyearweek
#'   iyw <- w[match("2018-30", w) + 0:211]
#'   lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
#'   set.seed(1)
#'   ens <- csfmt_ensemble_v4(
#'     data.table::data.table(location_code = "nation", isoyearweek = iyw),
#'     id_cols = "location_code",
#'     draws = list(cases = matrix(rpois(212 * 50, lam), nrow = 212))
#'   )
#'   ens <- mem_thresholds_v4(ens, measure = "cases")
#'   ens$data[
#'     isoyearweek %in% c("2021-45", "2022-02"),
#'     .(isoyearweek, cases_mem_thr_high, cases_mem_prob_high)
#'   ]
#' }
#' @export
mem_thresholds_v4 <- function(
  x,
  measure,
  min_seasons = 2,
  prefer_seasons = 5,
  i.seasons = 10,
  min_weeks_per_season = 30,
  exclude_seasons = NULL
) {
  .v4_validate_ensemble(x)
  if (!requireNamespace("mem", quietly = TRUE)) {
    stop("mem_thresholds_v4 requires the 'mem' package", call. = FALSE)
  }
  .v4_check_draw_measure(x, measure)
  nm <- .v4_mem_names(measure)
  .v4_check_names(unlist(nm, use.names = FALSE))

  Y <- .v4_draws(x, measure)
  weeks <- x$data[[x$time_col]]
  d <- data.table::data.table(
    season = cstime::isoyearweek_to_season_c(weeks),
    seasonweek = cstime::isoyearweek_to_seasonweek_n(weeks),
    point = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = x$data$time_series_id
  )
  if (length(exclude_seasons)) {
    hit <- intersect(exclude_seasons, unique(d$season))
    if (length(hit)) {
      message(
        "mem_thresholds_v4: excluding ",
        length(hit),
        " season(s) from the training baseline: ",
        paste(hit, collapse = ", ")
      )
    }
  }
  est <- .v4_mem_estimate_thresholds(
    d,
    min_seasons,
    prefer_seasons,
    i.seasons,
    min_weeks_per_season,
    exclude_seasons
  )
  if (length(est$provisional)) {
    message(
      "mem_thresholds_v4: ",
      length(est$provisional),
      " season(s) fit on < ",
      prefer_seasons,
      " training seasons (provisional); see ",
      nm$n_seasons,
      "."
    )
  }
  thr <- .v4_mem_week_thresholds(d, data.table::rbindlist(est$thr_all))

  # The level code is 1 plus the number of thresholds that the draw reaches.
  code <- 1L +
    (Y >= thr$mem_preepidemic) +
    (Y >= thr$mem_medium) +
    (Y >= thr$mem_high) +
    (Y >= thr$mem_veryhigh)
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- .V4_MEM_LEVELS

  out <- data.table::copy(x$data)
  out[, (nm$thr) := thr[, paste0("mem_", .V4_MEM_THRESHOLDS), with = FALSE]]
  out[, (nm$n_seasons) := thr$mem_n_seasons]
  out[, (nm$postepidemic) := thr$mem_postepidemic]
  out[, (nm$season_start) := thr$mem_season_start]
  out[, (nm$season_weeks) := thr$mem_season_weeks]
  .v4_collapse_status_into(out, nm$status, code, .V4_MEM_LEVELS)
  x$data <- out
  x$draws[[nm$status]] <- code
  .v4_validate_ensemble(x)
  return(x)
}

# The new names of a MEM step on `measure`. The caller checks them with
# .v4_check_names().
.v4_mem_names <- function(measure) {
  status <- paste0(measure, "_mem")
  return(list(
    status = status,
    thr = paste0(status, "_thr_", .V4_MEM_THRESHOLDS),
    n_seasons = paste0(status, "_n_seasons"),
    postepidemic = paste0(status, "_thr_postepidemic"),
    season_start = paste0(status, "_season_start"),
    season_weeks = paste0(status, "_season_weeks"),
    summary = .v4_status_names(status, .V4_MEM_LEVELS)
  ))
}

# The thresholds, the number of training seasons and the fit fields of each
# row of `d`. They come from the fits in `thr`, one row per series and
# season. A row whose season has no fit gets NA.
.v4_mem_week_thresholds <- function(d, thr) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  mem_n_seasons <- i.mem_preepidemic <- i.mem_medium <- i.mem_high <- NULL
  i.mem_veryhigh <- i.mem_n_seasons <- NULL
  mem_postepidemic <- mem_season_start <- mem_season_weeks <- NULL
  i.mem_postepidemic <- i.mem_season_start <- i.mem_season_weeks <- NULL
  w <- data.table::data.table(
    time_series_id = d$time_series_id,
    season = d$season
  )
  w[, (paste0("mem_", .V4_MEM_THRESHOLDS)) := NA_real_]
  w[, mem_n_seasons := NA_integer_]
  w[, mem_postepidemic := NA_real_]
  w[, mem_season_start := NA_integer_]
  w[, mem_season_weeks := NA_integer_]
  if (nrow(thr)) {
    w[
      thr,
      on = c("time_series_id", "season"),
      `:=`(
        mem_preepidemic = i.mem_preepidemic,
        mem_medium = i.mem_medium,
        mem_high = i.mem_high,
        mem_veryhigh = i.mem_veryhigh,
        mem_n_seasons = i.mem_n_seasons,
        mem_postepidemic = i.mem_postepidemic,
        mem_season_start = i.mem_season_start,
        mem_season_weeks = i.mem_season_weeks
      )
    ]
  }
  return(w)
}
