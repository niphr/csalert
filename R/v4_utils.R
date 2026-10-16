# Helpers that more than one v4 file uses. Each is a copy of a v3 or v1
# helper, so that the v4 files call no csalert function outside R/v4_*.R.

# A copy of isoyearweek_week_start(): the Monday that starts each ISO week, as
# a Date, with NA for a string that is not an ISO week.
.v4_isoyearweek_week_start <- function(isoyearweek) {
  cal <- cstime::dates_by_isoyearweek
  return(as.Date(cal$mon[match(isoyearweek, cal$isoyearweek)]))
}

# A copy of set_time_series_id(): add `time_series_label`, the identity values
# joined by the ASCII unit separator, and `time_series_id`, the xxhash64 digest of that label, to
# `d` by reference.
.v4_set_time_series_id <- function(d, id_cols, sep = "\037") {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  time_series_id <- time_series_label <- NULL
  i.time_series_id <- i.time_series_label <- NULL
  stopifnot(data.table::is.data.table(d), all(id_cols %in% names(d)))
  u <- unique(d[, id_cols, with = FALSE])
  key <- u[, do.call(paste, c(.SD, sep = sep)), .SDcols = id_cols]
  u[, time_series_label := key]
  u[,
    time_series_id := vapply(
      key,
      function(k) {
        return(digest::digest(k, algo = "xxhash64"))
      },
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

# A copy of row_mean().
.v4_row_mean <- function(x, na.rm = FALSE, dims = 1L) {
  return(rowMeans(x, na.rm, dims))
}

# A copy of row_sd(): the standard deviation of each row.
.v4_row_sd <- function(x, na.rm = FALSE) {
  return(sqrt(
    rowSums((x - rowMeans(x, na.rm = na.rm))^2, na.rm = na.rm) / (ncol(x) - 1)
  ))
}

# A copy of mem_extract_thresholds(): the four thresholds of a fitted
# mem::memmodel object.
.v4_mem_extract_thresholds <- function(fit) {
  return(data.table::data.table(
    mem_preepidemic = fit$epidemic.thresholds[1],
    mem_medium = fit$epi.intervals[1, 4],
    mem_high = fit$epi.intervals[2, 4],
    mem_veryhigh = fit$epi.intervals[3, 4]
  ))
}

# One quiet mem::memmodel() fit. NULL on an error.
.v4_mem_fit_quiet <- function(model_data, n_seasons, method) {
  f <- NULL
  utils::capture.output(suppressWarnings(suppressMessages(
    f <- tryCatch(
      if (is.null(method)) {
        mem::memmodel(model_data, i.seasons = n_seasons)
      } else {
        mem::memmodel(model_data, i.seasons = n_seasons, i.method = method)
      },
      error = function(e) {
        return(NULL)
      }
    )
  )))
  return(f)
}

# A copy of mem_fit(): fit MEM, and fit again with i.method = 3 when the
# default method fails. NULL when both fail, and when fewer than 2 seasons
# hold a count above 0.
.v4_mem_fit <- function(model_data, i.seasons = 10) {
  if (is.null(model_data) || ncol(model_data) < 1) {
    return(NULL)
  }
  nonzero <- vapply(
    model_data,
    function(v) {
      return(any(v > 0, na.rm = TRUE))
    },
    logical(1)
  )
  if (sum(nonzero) < 2) {
    return(NULL)
  }
  n_seasons <- min(i.seasons, ncol(model_data))
  fit <- .v4_mem_fit_quiet(model_data, n_seasons, NULL)
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1])) {
    fit <- .v4_mem_fit_quiet(model_data, n_seasons, 3)
  }
  if (is.null(fit) || is.na(fit$epidemic.thresholds[1])) {
    return(NULL)
  }
  return(fit)
}

# A copy of mem_estimate_thresholds(): leave-future-out MEM thresholds for
# every season of every series. `d` holds `time_series_id`, `season`,
# `seasonweek` and `point`. A season is fit only on the seasons before it.
.v4_mem_estimate_thresholds <- function(
  d,
  min_seasons,
  prefer_seasons,
  i.seasons,
  min_weeks_per_season,
  exclude_seasons
) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  seasonweek <- time_series_id <- NULL
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
    week_counts <- vapply(
      m,
      function(v) {
        return(sum(!is.na(v)))
      },
      integer(1)
    )
    train_ok <- names(week_counts)[week_counts >= min_weeks_per_season]
    for (s in sort(unique(ds$season))) {
      prior <- setdiff(train_ok[train_ok < s], exclude_seasons)
      if (length(prior) < min_seasons) {
        next
      }
      # Keep the latest i.seasons BEFORE na.omit(), so that older seasons with
      # gaps do not remove season weeks from the fit.
      prior <- utils::tail(prior, i.seasons)
      fit <- .v4_mem_fit(
        stats::na.omit(m[, prior, with = FALSE]),
        i.seasons = i.seasons
      )
      if (is.null(fit)) {
        next
      }
      res <- .v4_mem_extract_thresholds(fit)
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
  return(list(thr_all = thr_all, provisional = provisional))
}

# A copy of collapse_status_into(): reduce an ordinal status code matrix,
# codes 1 to K, to one probability column per level and one ordinal quantile
# column per probability, added to `d` by reference.
.v4_collapse_status_into <- function(d, measure, M, levs, probs) {
  K <- length(levs)
  n <- nrow(M)
  prob <- vapply(
    seq_len(K),
    function(k) {
      return(rowMeans(M == k, na.rm = TRUE))
    },
    numeric(n)
  )
  pcols <- vapply(
    levs,
    function(L) {
      return(.v4_var(measure, level = L))
    },
    character(1)
  )
  d[, (pcols) := data.table::as.data.table(prob)]

  # the ordinal p-quantile is the lowest level whose cumulative probability
  # reaches p
  cum <- matrixStats::rowCumsums(prob)
  qmat <- vapply(
    probs,
    function(p) {
      return(pmin(rowSums(cum < p) + 1L, K))
    },
    numeric(n)
  )
  qmat <- matrix(qmat, nrow = n, ncol = length(probs))
  qcols <- vapply(
    probs,
    function(p) {
      return(.v4_var(measure, q = p))
    },
    character(1)
  )
  d[, (qcols) := data.table::as.data.table(qmat)]
  return(invisible(d))
}
