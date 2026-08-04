# MEM (Moving Epidemic Method) intensity thresholds on a csfmt_ensemble_v3.
#
# Two parts (see design doc):
#   (1) ESTIMATE thresholds from the POINT history (median of the draws), per
#       season, leave-future-out -- draw-independent, since historical weeks are
#       final. Attaches per-week threshold columns to $data (for plotting bands).
#   (2) CLASSIFY every DRAW of every week against its season's thresholds -> an
#       ordinal status code matrix in $draws. This is what propagates nowcast
#       uncertainty into the alert level, so it runs BEFORE collapse.
#
# Ordinal levels (codes 1..5):
#   1 preepidemic  (< onset)         2 low     3 medium     4 high     5 veryhigh
# A week with NA thresholds (too little history) gets NA status.

# Extract the four thresholds from a fitted mem::memmodel object.
mem_extract_thresholds <- function(fit) {
  data.table::data.table(
    mem_preepidemic = fit$epidemic.thresholds[1], # onset (pre-epidemic)
    mem_medium = fit$epi.intervals[1, 4], # 40%
    mem_high = fit$epi.intervals[2, 4], # 90%
    mem_veryhigh = fit$epi.intervals[3, 4] # 97.5%
  )
}

# Fit MEM, with the norsyss fallback to i.method = 3. NULL on failure.
mem_fit <- function(model_data, i.seasons = 10) {
  if (is.null(model_data) || ncol(model_data) < 1) {
    return(NULL)
  }
  # Non-zero-season guard: MEM needs >= 2 training seasons with real (non-zero)
  # signal. Sparse count series (flu deaths, RSV hospitalisations) can have whole
  # but near-all-zero seasons; skip cleanly rather than let mem::memmodel error
  # ("at least two seasons of valid data ... required") and spam the run log.
  if (
    sum(vapply(model_data, function(v) any(v > 0, na.rm = TRUE), logical(1))) <
      2
  ) {
    return(NULL)
  }
  n_seasons <- min(i.seasons, ncol(model_data))
  # Quiet: mem::memmodel can print/warn on marginal data; surface NA, not noise.
  fit_quiet <- function(method) {
    f <- NULL
    utils::capture.output(suppressWarnings(suppressMessages(
      f <- tryCatch(
        if (is.null(method)) {
          mem::memmodel(model_data, i.seasons = n_seasons)
        } else {
          mem::memmodel(model_data, i.seasons = n_seasons, i.method = method)
        },
        error = function(e) NULL
      )
    )))
    f
  }
  fit <- fit_quiet(NULL)
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1])) {
    fit <- fit_quiet(3)
  }
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1])) {
    return(NULL)
  }
  fit
}

#' MEM intensity thresholds
#' @param x Data object.
#' @param ... Passed to methods.
#' @seealso \code{vignette("nowcasting", package = "csalert")} names this function
#'   in its closing "Where next" list but does not demonstrate it; the example
#'   below is its only worked demonstration.
#' @examples
#' # MEM needs several complete prior seasons, so this fixture spans four:
#' # 212 weeks with a winter peak in each.
#' if (requireNamespace("mem", quietly = TRUE)) {
#'   w <- cstime::dates_by_isoyearweek$isoyearweek
#'   i <- match("2018-30", w)
#'   n <- 212L
#'   iyw <- w[i + 0:(n - 1)]
#'   set.seed(1)
#'   lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
#'   ens <- csfmt_ensemble_v3(
#'     data.table::data.table(
#'       isoyearweek = iyw, location_code = "nation", age = "total"
#'     ),
#'     id_cols = c("location_code", "age"),
#'     draws = list(numerator_nowcasted = matrix(rpois(n * 50, lam), nrow = n))
#'   )
#'
#'   ens <- mem_thresholds_v1(ens, measure = "numerator_nowcasted")
#'
#'   # thresholds are estimated leave-future-out, so the early seasons get none
#'   print(unique(ens$data[
#'     !is.na(mem_high),
#'     .(
#'       season = cstime::isoyearweek_to_season_c(isoyearweek),
#'       mem_preepidemic, mem_medium, mem_high, mem_veryhigh, mem_n_seasons
#'     )
#'   ]))
#'
#'   # A week whose season has no thresholds gets NA for every draw, so it is not
#'   # classified at all. On this fixture that is the first two seasons:
#'   status <- ens$draws$numerator_nowcasted_status
#'   print(c(
#'     weeks = nrow(status),
#'     weeks_with_no_threshold = sum(apply(status, 1, function(r) all(is.na(r))))
#'   ))
#'
#'   # For a week that DOES have thresholds, every draw is classified, so the
#'   # alert level arrives as a distribution rather than as a single label.
#'   r <- ens_collapse(ens, probs = 0.5)
#'   pcols <- grep("_status_prob_", names(r), value = TRUE)
#'   print(r[
#'     isoyearweek %in% c("2021-45", "2022-02"),
#'     c("isoyearweek", pcols),
#'     with = FALSE
#'   ])
#' }
#' @rdname mem_thresholds_v1
#' @export
mem_thresholds_v1 <- function(x, ...) {
  UseMethod("mem_thresholds_v1")
}

#' @method mem_thresholds_v1 csfmt_ensemble_v3
#' @rdname mem_thresholds_v1
#' @param measure The `$draws` measure to threshold on (a rate or count).
#' @param min_seasons Hard floor of complete prior seasons needed to fit.
#' @param prefer_seasons Preferred training depth (provisional below this).
#' @param i.seasons Max seasons passed to mem::memmodel.
#' @param min_weeks_per_season Weeks needed for a season to count as training.
#' @param exclude_seasons Optional character vector of seasons (e.g.
#'   `c("2009/2010", "2019/2020")`, the `isoyearweek_to_season_c` form) to drop
#'   from the MEM training baseline -- anomalous seasons (pandemic years, data
#'   gaps) that would distort the thresholds. Thresholds are still ESTIMATED for
#'   every season (including excluded ones) from its remaining non-excluded prior
#'   seasons; only the baseline they are fit on changes.
#' @returns The `csfmt_ensemble_v3` with per-draw MEM intensity columns added to
#'   `$draws` (the ordinal 1..5 status for `measure` and its threshold levels), so
#'   the intensity level propagates through the later quantile collapse.
#' @export
mem_thresholds_v1.csfmt_ensemble_v3 <- function(
  x,
  measure,
  min_seasons = 2,
  prefer_seasons = 5,
  i.seasons = 10,
  min_weeks_per_season = 30,
  exclude_seasons = NULL,
  ...
) {
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  if (!requireNamespace("mem", quietly = TRUE)) {
    stop("mem_thresholds_v1 requires the 'mem' package")
  }
  if (!measure %in% names(x$draws)) {
    stop(sprintf("measure '%s' not in $draws", measure))
  }

  Y <- x$draws[[measure]]
  d <- data.table::data.table(
    season = cstime::isoyearweek_to_season_c(x$data$isoyearweek),
    seasonweek = cstime::isoyearweek_to_seasonweek_n(x$data$isoyearweek),
    point = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = x$data$time_series_id
  )

  # (1) estimate per-season leave-future-out thresholds, per time series.
  #     prefer_seasons training seasons are preferred; a season fit on fewer (but
  #     >= min_seasons) is computed but flagged provisional via mem_n_seasons.
  if (length(exclude_seasons)) {
    hit <- intersect(exclude_seasons, unique(d$season))
    if (length(hit)) {
      message(
        "mem_thresholds_v1: excluding ",
        length(hit),
        " season(s) from the training baseline: ",
        paste(hit, collapse = ", ")
      )
    }
  }

  thr_all <- list()
  provisional <- character(0)
  for (tsid in unique(d$time_series_id)) {
    ds <- d[time_series_id == tsid]
    m <- data.table::dcast.data.table(
      ds,
      seasonweek ~ season,
      value.var = "point"
    )
    m[, seasonweek := NULL]
    week_counts <- vapply(m, function(v) sum(!is.na(v)), integer(1))
    train_ok <- names(week_counts)[week_counts >= min_weeks_per_season]
    for (s in sort(unique(ds$season))) {
      prior <- train_ok[train_ok < s]
      # drop anomalous seasons from the training baseline (thresholds are still
      # estimated for `s` itself, just not fit on the excluded seasons)
      if (length(exclude_seasons)) {
        prior <- setdiff(prior, exclude_seasons)
      }
      if (length(prior) < min_seasons) {
        next
      }
      # Keep only the most recent i.seasons BEFORE na.omit: memmodel uses the last
      # i.seasons anyway, and na.omit over older (often partially-covered) seasons
      # would needlessly drop seasonweeks and starve the fit -> NA thresholds.
      prior <- utils::tail(prior, i.seasons)
      fit <- mem_fit(
        stats::na.omit(m[, prior, with = FALSE]),
        i.seasons = i.seasons
      )
      if (is.null(fit)) {
        next
      }
      res <- mem_extract_thresholds(fit)
      res[, `:=`(
        season = s,
        time_series_id = tsid,
        mem_n_seasons = length(prior)
      )]
      thr_all[[paste(tsid, s)]] <- res
      if (length(prior) < prefer_seasons) {
        provisional <- c(provisional, paste(tsid, s))
      }
    }
  }
  thr <- data.table::rbindlist(thr_all)
  if (length(provisional)) {
    message(
      "mem_thresholds_v1: ",
      length(provisional),
      " season(s) fit on < ",
      prefer_seasons,
      " training seasons (provisional); see mem_n_seasons."
    )
  }

  # attach per-week threshold columns to $data (NA where unfit)
  x$data[,
    c("mem_preepidemic", "mem_medium", "mem_high", "mem_veryhigh") := NA_real_
  ]
  x$data[, mem_n_seasons := NA_integer_]
  if (nrow(thr)) {
    i.mem_preepidemic <- i.mem_medium <- i.mem_high <- i.mem_veryhigh <- i.mem_n_seasons <- NULL
    x$data[, .season := cstime::isoyearweek_to_season_c(isoyearweek)]
    x$data[
      thr,
      on = c("time_series_id", ".season==season"),
      `:=`(
        mem_preepidemic = i.mem_preepidemic,
        mem_medium = i.mem_medium,
        mem_high = i.mem_high,
        mem_veryhigh = i.mem_veryhigh,
        mem_n_seasons = i.mem_n_seasons
      )
    ]
    x$data[, .season := NULL]
  }

  # (2) classify every draw against its week's thresholds -> ordinal code 1..5
  code <- 1L +
    (Y >= x$data$mem_preepidemic) +
    (Y >= x$data$mem_medium) +
    (Y >= x$data$mem_high) +
    (Y >= x$data$mem_veryhigh)
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- c("preepidemic", "low", "medium", "high", "veryhigh")
  x$draws[[csfmt_var(measure, role = "status")]] <- code

  validate_ensemble(x)
}
