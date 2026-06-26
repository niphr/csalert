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
    mem_preepidemic = fit$epidemic.thresholds[1],  # onset (pre-epidemic)
    mem_medium      = fit$epi.intervals[1, 4],       # 40%
    mem_high        = fit$epi.intervals[2, 4],       # 90%
    mem_veryhigh    = fit$epi.intervals[3, 4]        # 97.5%
  )
}

# Fit MEM, with the norsyss fallback to i.method = 3. NULL on failure.
mem_fit <- function(model_data, i.seasons = 10) {
  if (is.null(model_data) || ncol(model_data) < 1) return(NULL)
  n_seasons <- min(i.seasons, ncol(model_data))
  fit <- tryCatch(mem::memmodel(model_data, i.seasons = n_seasons), error = function(e) NULL)
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1]))
    fit <- tryCatch(mem::memmodel(model_data, i.seasons = n_seasons, i.method = 3),
                    error = function(e) NULL)
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1])) return(NULL)
  fit
}

#' MEM intensity thresholds
#' @param x Data object.
#' @param ... Passed to methods.
#' @rdname mem_thresholds
#' @export
mem_thresholds <- function(x, ...) {
  UseMethod("mem_thresholds")
}

#' @method mem_thresholds csfmt_ensemble_v3
#' @rdname mem_thresholds
#' @param measure The `$draws` measure to threshold on (a rate or count).
#' @param min_seasons Hard floor of complete prior seasons needed to fit.
#' @param prefer_seasons Preferred training depth (provisional below this).
#' @param i.seasons Max seasons passed to mem::memmodel.
#' @param min_weeks_per_season Weeks needed for a season to count as training.
#' @export
mem_thresholds.csfmt_ensemble_v3 <- function(x, measure, min_seasons = 2,
                                          prefer_seasons = 5, i.seasons = 10,
                                          min_weeks_per_season = 30, ...) {
  stopifnot(inherits(x, "csfmt_ensemble_v3"))
  if (!requireNamespace("mem", quietly = TRUE))
    stop("mem_thresholds requires the 'mem' package")
  if (!measure %in% names(x$draws))
    stop(sprintf("measure '%s' not in $draws", measure))

  Y <- x$draws[[measure]]
  d <- data.table::data.table(
    season         = cstime::isoyearweek_to_season_c(x$data$isoyearweek),
    seasonweek     = cstime::isoyearweek_to_seasonweek_n(x$data$isoyearweek),
    point          = matrixStats::rowMedians(Y, na.rm = TRUE),
    time_series_id = x$data$time_series_id
  )

  # (1) estimate per-season leave-future-out thresholds, per time series
  thr_all <- list()
  for (tsid in unique(d$time_series_id)) {
    ds <- d[time_series_id == tsid]
    m <- data.table::dcast.data.table(ds, seasonweek ~ season, value.var = "point")
    m[, seasonweek := NULL]
    week_counts <- vapply(m, function(v) sum(!is.na(v)), integer(1))
    train_ok <- names(week_counts)[week_counts >= min_weeks_per_season]
    for (s in sort(unique(ds$season))) {
      prior <- train_ok[train_ok < s]
      if (length(prior) < min_seasons) next
      fit <- mem_fit(stats::na.omit(m[, prior, with = FALSE]), i.seasons = i.seasons)
      if (is.null(fit)) next
      res <- mem_extract_thresholds(fit)
      res[, `:=`(season = s, time_series_id = tsid)]
      thr_all[[paste(tsid, s)]] <- res
    }
  }
  thr <- data.table::rbindlist(thr_all)

  # attach per-week threshold columns to $data (NA where unfit)
  x$data[, c("mem_preepidemic", "mem_medium", "mem_high", "mem_veryhigh") := NA_real_]
  if (nrow(thr)) {
    i.mem_preepidemic <- i.mem_medium <- i.mem_high <- i.mem_veryhigh <- NULL
    x$data[, .season := cstime::isoyearweek_to_season_c(isoyearweek)]
    x$data[thr, on = c("time_series_id", ".season==season"), `:=`(
      mem_preepidemic = i.mem_preepidemic, mem_medium = i.mem_medium,
      mem_high = i.mem_high, mem_veryhigh = i.mem_veryhigh)]
    x$data[, .season := NULL]
  }

  # (2) classify every draw against its week's thresholds -> ordinal code 1..5
  code <- 1L + (Y >= x$data$mem_preepidemic) + (Y >= x$data$mem_medium) +
    (Y >= x$data$mem_high) + (Y >= x$data$mem_veryhigh)
  code <- matrix(as.integer(code), nrow = nrow(Y), ncol = ncol(Y))
  attr(code, "levels") <- c("preepidemic", "low", "medium", "high", "veryhigh")
  x$draws[[csfmt_var(measure, role = "status")]] <- code

  validate_ensemble(x)
}
