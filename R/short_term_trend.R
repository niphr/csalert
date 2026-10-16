# The naming prefix for one side of the rate. `from` is the prefix value that
# means "take it from the column name". The literal "generic" means "use
# `generic_word`". Anything else is used as written.
stt_v1_prefix <- function(column, naming_prefix, from, generic_word) {
  if (naming_prefix == from) {
    return(stringr::str_remove(column, "_[a-z]+$"))
  }
  if (naming_prefix == "generic") {
    return(generic_word)
  }
  return(naming_prefix)
}

# The status and doubling-days column names. "universal" leaves the window
# width as the only distinguishing part; anything else appends `tail`, which is
# the per-X suffix for a rate and the measure suffix for a count.
stt_v1_status_varnames <- function(base, trend_dates, naming_prefix, tail) {
  if (naming_prefix == "universal") {
    return(list(
      trend = paste0(base, "_trend0_", trend_dates, "_status"),
      dates_to_double = paste0(base, "_doublingdays0_", trend_dates)
    ))
  }
  return(list(
    trend = paste0(base, "_trend0_", trend_dates, tail, "_status"),
    dates_to_double = paste0(base, "_doublingdays0_", trend_dates, tail)
  ))
}

# The status levels, in the order the factor takes them.
stt_v1_status_levels <- function(include_decreasing) {
  if (include_decreasing) {
    return(c("training", "forecast", "decreasing", "null", "increasing"))
  }
  return(c("training", "forecast", "notincreasing", "increasing"))
}

# The status of each window from its slope and p-value. Without
# `include_decreasing` the test is one-sided: a significant negative slope is
# "notincreasing", the same label a flat series gets.
stt_v1_status <- function(pval, co, alpha, include_decreasing) {
  if (!include_decreasing) {
    return(ifelse(pval <= alpha & co > 0, "increasing", "notincreasing"))
  }
  ifelse(pval > alpha, "null", ifelse(co < 0, "decreasing", "increasing"))
}

# The kernel's fit of the window that ends at row `i`, as the forecast needs
# it. NULL when the fit did not converge, or when its counts are separated.
stt_v1_last_fit <- function(k, i) {
  if (!k$converged[i, 1] || k$separated[i, 1]) {
    return(NULL)
  }
  list(
    beta0 = k$beta0[i, 1],
    beta1 = k$beta1[i, 1],
    var_b0 = k$var_b0[i, 1],
    cov_b0b1 = k$cov_b0b1[i, 1],
    var_b1 = k$se[i, 1]^2,
    phi = k$phi[i, 1]
  )
}

# Fit every rolling window with the v4 kernel, and label its status.
#
# .v4_rolling_qp_offset() fits all windows of the series at once. It drops the
# rows with an NA count or denominator from a window, and it fits a window
# only when at least 3 rows remain. The first rule that holds gives a window
# its status and doubling time:
# 1. A window with NA rows and fewer than 3 rows left gets no status and no
#    doubling time.
# 2. A window where every count left is 0 gets "notincreasing", or "null" with
#    `include_decreasing`, and no doubling time. This rule holds at every
#    width, also at width 2.
# 3. A window gets no status and no doubling time when its fit does not
#    converge, has a non-finite value, or has separated counts. The kernel
#    fits no window of fewer than 3 rows. So a window of width 2 with a count
#    above 0 falls under this rule.
# 4. Every other window gets the status and doubling time from the kernel's
#    slope and p-value.
#
# `forecast` and `forecast_denominator` are the kernel's fits of the LAST
# window, which the caller uses for the forecast. They are NULL when that fit
# gives no forecast.
stt_v1_fit_windows <- function(
  x,
  with_pred,
  trend,
  doubling_time,
  trend_rows,
  remove_last_rows,
  varname_forecast_numerator,
  varname_forecast_denominator,
  denominator,
  include_decreasing,
  alpha,
  gran_time
) {
  n_fit <- nrow(x) - remove_last_rows
  rows <- seq_len(n_fit)
  if (n_fit < trend_rows) {
    return(list(
      trend = trend,
      doubling_time = doubling_time,
      forecast = NULL,
      forecast_denominator = NULL
    ))
  }

  # A zero denominator becomes 1 before the log.
  tv <- with_pred[["trend_variable"]][rows]
  log_den <- NULL
  if (!is.null(denominator)) {
    den <- as.numeric(with_pred[[varname_forecast_denominator]][rows])
    den[!is.na(den) & den == 0] <- 1
    log_den <- matrix(log(den))
  }
  k <- .v4_rolling_qp_offset(
    Y = matrix(as.numeric(with_pred[[varname_forecast_numerator]][rows])),
    OFF = log_den,
    TT = matrix(tv),
    width = trend_rows,
    na_rm = TRUE,
    extended = TRUE
  )

  windows <- trend_rows:n_fit
  # The minimum of 3 rows applies only to a window with NA rows.
  n_used <- k$n_used[windows, 1]
  too_few <- n_used < trend_rows & n_used < .V4_MIN_ROWS
  all_zero <- !too_few & k$n_pos[windows, 1] == 0
  fitted <- k$converged[windows, 1] & !k$separated[windows, 1] & !all_zero

  i <- windows[fitted]
  co <- k$beta1[i, 1]
  trend[i] <- stt_v1_status(k$p[i, 1], co, alpha, include_decreasing)
  doubling_time[i] <- nrow(with_pred) * log(2) / co # remember to scale it so that it is per date!!
  if (gran_time == "isoyearweek") {
    doubling_time[i] <- doubling_time[i] * 7 # remember to scale it so that it is per date!!
  }
  trend[windows[all_zero]] <- if (include_decreasing) {
    "null"
  } else {
    "notincreasing"
  }

  # The forecast uses the fit of the last window. The denominator fit has no
  # offset.
  forecast <- stt_v1_last_fit(k, n_fit)
  forecast_denominator <- NULL
  if (!is.null(denominator)) {
    last <- (n_fit - trend_rows + 1):n_fit
    k_den <- .v4_rolling_qp_offset(
      Y = matrix(den[last]),
      TT = matrix(tv[last]),
      width = trend_rows,
      na_rm = TRUE,
      extended = TRUE
    )
    forecast_denominator <- stt_v1_last_fit(k_den, trend_rows)
  }
  return(list(
    trend = trend,
    doubling_time = doubling_time,
    forecast = forecast,
    forecast_denominator = forecast_denominator
  ))
}

# The forecast and its 95% prediction interval at time values `t0`, from a fit
# of stt_v1_last_fit(). The formula is that of prediction_interval.glm():
# se = sqrt(phi * mu0 + mu0^2 * se_link^2), where se_link^2 = x0' V x0 and V
# is the scaled covariance of the intercept and the slope. All three values
# are NA when any step warns or errors.
stt_v1_prediction_interval <- function(fit, t0, offset) {
  tryCatch(
    {
      # mu0 uses the inverse link of stats::quasipoisson(), pmax(exp(eta),
      # .Machine$double.eps). predict.glm(type = "response") inside
      # prediction_interval.glm() uses the same inverse link. As there, the
      # lower and upper bounds are not clamped at 0, and the lower bound can
      # be negative.
      mu0 <- pmax(
        exp(fit$beta0 + fit$beta1 * t0 + offset),
        .Machine$double.eps
      )
      se_link2 <- fit$var_b0 + 2 * t0 * fit$cov_b0b1 + t0^2 * fit$var_b1
      se_fit <- sqrt(se_link2) * mu0
      tau <- fit$phi + se_fit^2 / mu0
      se <- sqrt(mu0 * tau)
      z <- stats::qnorm(1 - 0.05 / 2)
      data.table(lower = mu0 - z * se, point = mu0, upper = mu0 + z * se)
    },
    warning = function(cond) {
      data.table(
        lower = rep(NA_real_, length(t0)),
        point = rep(NA_real_, length(t0)),
        upper = rep(NA_real_, length(t0))
      )
    },
    error = function(cond) {
      data.table(
        lower = rep(NA_real_, length(t0)),
        point = rep(NA_real_, length(t0)),
        upper = rep(NA_real_, length(t0))
      )
    }
  )
}


# Write the forecast and its prediction interval into `with_pred`, by
# reference. A missing fit blanks every forecast column instead of leaving the
# training values in place.
stt_v1_forecast <- function(
  with_pred,
  forecast,
  forecast_denominator,
  denominator,
  prX,
  varname_forecast_numerator,
  varname_forecast_denominator,
  varname_forecast_predinterval_q02x5_numerator,
  varname_forecast_predinterval_q97x5_numerator,
  varname_forecast_prX,
  varname_forecast_predinterval_q02x5_prX,
  varname_forecast_predinterval_q97x5_prX
) {
  to_be_forecasted <- NULL
  # prediction interval
  if (
    is.null(forecast) ||
      (!is.null(denominator) && is.null(forecast_denominator))
  ) {
    # Without a denominator, `varname_forecast_denominator` is not defined.
    if (!is.null(denominator)) {
      suppressWarnings(with_pred[
        to_be_forecasted == TRUE,
        (varname_forecast_denominator) := NA_real_
      ])
    }
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_numerator) := NA_real_
    ])
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_predinterval_q02x5_numerator) := NA_real_
    ])
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_predinterval_q97x5_numerator) := NA_real_
    ])

    if (!is.null(denominator)) {
      with_pred[, (varname_forecast_prX) := NA_real_]
      with_pred[, (varname_forecast_predinterval_q02x5_prX) := NA_real_]
      with_pred[, (varname_forecast_predinterval_q97x5_prX) := NA_real_]
    }
  } else {
    t0 <- with_pred[to_be_forecasted == TRUE][["trend_variable"]]
    offset <- 0
    if (!is.null(denominator)) {
      # The denominator forecast is the point of the denominator fit.
      forecasted_denominator <- pmax(
        exp(forecast_denominator$beta0 + forecast_denominator$beta1 * t0),
        .Machine$double.eps
      )
      suppressWarnings(with_pred[
        to_be_forecasted == TRUE,
        (varname_forecast_denominator) := round(forecasted_denominator)
      ])
      # if denominator is zero, replace with 1
      with_pred[
        to_be_forecasted == TRUE & get(varname_forecast_denominator) == 0,
        (varname_forecast_denominator) := 1
      ]
      offset <- log(
        with_pred[to_be_forecasted == TRUE][[varname_forecast_denominator]]
      )
    }

    forecasted <- stt_v1_prediction_interval(forecast, t0, offset)
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_numerator) := round(forecasted$point)
    ])
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_predinterval_q02x5_numerator) := round(forecasted$lower)
    ])
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_predinterval_q97x5_numerator) := round(forecasted$upper)
    ])

    if (!is.null(denominator)) {
      # if numerator is predicted to be bigger than denominator, set numerator to denominator
      # todo: this probably should be fixed
      with_pred[
        get(varname_forecast_numerator) > get(varname_forecast_denominator),
        (varname_forecast_numerator) := get(varname_forecast_denominator)
      ]

      for (i in seq_along(prX)) {
        with_pred[,
          (varname_forecast_prX[i]) := prX[i] *
            get(varname_forecast_numerator) /
            get(varname_forecast_denominator)
        ]
        with_pred[
          is.nan(get(varname_forecast_prX[i])),
          (varname_forecast_prX[i]) := 0
        ]

        with_pred[,
          (varname_forecast_predinterval_q02x5_prX[i]) := prX[i] *
            get(varname_forecast_predinterval_q02x5_numerator) /
            get(varname_forecast_denominator)
        ]
        with_pred[
          is.nan(get(varname_forecast_predinterval_q02x5_prX[i])),
          (varname_forecast_predinterval_q02x5_prX[i]) := 0
        ]

        with_pred[,
          (varname_forecast_predinterval_q97x5_prX[i]) := prX[i] *
            get(varname_forecast_predinterval_q97x5_numerator) /
            get(varname_forecast_denominator)
        ]
        with_pred[
          is.nan(get(varname_forecast_predinterval_q97x5_prX[i])),
          (varname_forecast_predinterval_q97x5_prX[i]) := 0
        ]
      }
    }
  }
  return(invisible(with_pred))
}


short_term_trend_internal <- function(
  x,
  numerator,
  denominator = NULL,
  prX = 100,
  trend_isoyearweeks = 6,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = trend_isoyearweeks,
  numerator_naming_prefix = "from_numerator",
  denominator_naming_prefix = "from_denominator",
  statistics_naming_prefix = "universal",
  remove_training_data = FALSE,
  include_decreasing = FALSE,
  alpha = 0.05
) {
  to_be_forecasted <- NULL
  trend_variable <- NULL

  # check number of ts. can only process 1 for now
  num_unique_ts <- cstidy::unique_time_series(x) |>
    nrow()
  if (num_unique_ts > 1) {
    stop("There is more than 1 time series in this dataset", call. = FALSE)
  }

  # check granularity time. can only do date and isoyearweek
  gran_time <- x$granularity_time[1]
  if (!gran_time %in% c("isoyearweek")) {
    stop("granularity_time is not isoyearweek", call. = FALSE)
  }

  # weekly vs daily
  # create with_pred

  # must have more than 2 weeks data
  if (trend_isoyearweeks < 2) {
    stop(
      "trend_isoyearweeks must be >= 2 when granularity_time is isoyearweek",
      call. = FALSE
    )
  }
  trend_rows <- trend_isoyearweeks
  remove_last_rows <- remove_last_isoyearweeks
  forecast_rows <- forecast_isoyearweeks

  trend_dates <- trend_isoyearweeks * 7 - 1
  # ??
  with_pred <- cstidy::expand_time_to(
    x,
    max_isoyearweek = cstime::date_to_isoyearweek_c(
      max(x$date) + forecast_isoyearweeks * 7
    )
  )

  suffix <- stringr::str_extract(numerator, "_[a-z]+$")
  prefix <- stt_v1_prefix(
    numerator,
    numerator_naming_prefix,
    "from_numerator",
    "numerator"
  )
  prefix_denom <- stt_v1_prefix(
    denominator,
    denominator_naming_prefix,
    "from_denominator",
    "denominator"
  )

  prefix_pr100 <- paste0(prefix, "_vs_", prefix_denom)

  # create forecast var names (num, denom)
  varname_forecast_numerator <- paste0(prefix, "_forecasted", suffix)
  varname_forecast_predinterval_q02x5_numerator <- paste0(
    prefix,
    "_forecasted_predinterval_q02x5",
    suffix
  )
  varname_forecast_predinterval_q97x5_numerator <- paste0(
    prefix,
    "_forecasted_predinterval_q97x5",
    suffix
  )
  varname_forecast_numerator <- paste0(prefix, "_forecasted", suffix)
  if (!is.null(denominator)) {
    varname_forecast_denominator <- paste0(prefix_denom, "_forecasted", suffix)

    varname_forecast_prX <- paste0(
      prefix_pr100,
      "_forecasted_pr",
      formatC(prX, format = "f", digits = 0)
    )
    varname_forecast_prX_is_forecast <- paste0(
      prefix_pr100,
      "_forecasted_pr",
      formatC(prX, format = "f", digits = 0),
      "_forecast"
    )
    varname_forecast_predinterval_q02x5_prX <- paste0(
      prefix_pr100,
      "_forecasted_predinterval_q02x5_pr",
      formatC(prX, format = "f", digits = 0)
    )
    varname_forecast_predinterval_q97x5_prX <- paste0(
      prefix_pr100,
      "_forecasted_predinterval_q97x5_pr",
      formatC(prX, format = "f", digits = 0)
    )

    nm <- stt_v1_status_varnames(
      prefix_pr100,
      trend_dates,
      statistics_naming_prefix,
      paste0("_pr", formatC(prX, format = "f", digits = 0))
    )
    varname_trend <- nm$trend
    varname_dates_to_double <- nm$dates_to_double

    varname_forecast <- c(
      paste0(varname_forecast_numerator, "_forecast"),
      paste0(varname_forecast_prX, "_forecast")
    )
  } else {
    nm <- stt_v1_status_varnames(
      prefix,
      trend_dates,
      statistics_naming_prefix,
      suffix
    )
    varname_trend <- nm$trend
    varname_dates_to_double <- nm$dates_to_double

    varname_forecast <- paste0(varname_forecast_numerator, "_forecast")
  }

  # training/forecast period
  with_pred[, to_be_forecasted := FALSE]
  with_pred[
    (.N - remove_last_rows - forecast_rows + 1):.N,
    to_be_forecasted := TRUE
  ]

  with_pred[, (varname_forecast_numerator) := get(numerator)]
  if (!is.null(denominator)) {
    with_pred[, (varname_forecast_denominator) := get(denominator)]
  }
  with_pred[, trend_variable := seq_len(.N) / .N]

  doubling_time <- rep(NA_real_, nrow(with_pred))

  # trend
  # training period
  trend <- rep(NA_character_, nrow(with_pred))
  trend[1:(trend_rows - 1)] <- "training"
  trend[
    (length(trend) - remove_last_rows - forecast_rows + 1):length(trend)
  ] <- "forecast"

  fitted <- stt_v1_fit_windows(
    x,
    with_pred,
    trend,
    doubling_time,
    trend_rows,
    remove_last_rows,
    varname_forecast_numerator,
    varname_forecast_denominator,
    denominator,
    include_decreasing,
    alpha,
    gran_time
  )
  trend <- fitted$trend
  doubling_time <- fitted$doubling_time
  trend <- factor(trend, levels = stt_v1_status_levels(include_decreasing))
  stt_v1_forecast(
    with_pred,
    fitted$forecast,
    fitted$forecast_denominator,
    denominator,
    prX,
    varname_forecast_numerator,
    varname_forecast_denominator,
    varname_forecast_predinterval_q02x5_numerator,
    varname_forecast_predinterval_q97x5_numerator,
    varname_forecast_prX,
    varname_forecast_predinterval_q02x5_prX,
    varname_forecast_predinterval_q97x5_prX
  )

  with_pred[, trend_variable := NULL]
  for (i in varname_forecast) {
    with_pred[, (i) := to_be_forecasted]
  }
  with_pred[, to_be_forecasted := NULL]

  with_pred[, (varname_trend) := trend]
  with_pred[, (varname_dates_to_double) := round(doubling_time, 1)]

  if (remove_training_data) {
    with_pred <- with_pred[-(1:(trend_rows - 1))]
  }

  return(with_pred)
}

#' Estimate the short-term trend of a series
#'
#' @description
#' The `csfmt_ensemble_v3` method fits a line through a rolling window of weeks in
#' every draw. The `csfmt_rts_data_v1` table method fits a rolling
#' quasi-Poisson regression to a table, after Benedetti (2019)
#' <doi:10.5588/pha.19.0002>.
#' @param x A `csfmt_ensemble_v3`, or a `csfmt_rts_data_v1` table.
#' @param ... Passed to the method.
#' @family ensemble operations
#' @family short-term trend functions
#' @seealso `vignette("pipeline", package = "csalert")`, stage 5, and
#'   `vignette("csalert", package = "csalert")` on which method to use.
#' @examples
#' # the ensemble method: 10 weeks x 200 draws of a rising count
#' set.seed(1)
#' ens <- csfmt_ensemble_v3(
#'   data.table::data.table(
#'     isoyearweek = sprintf("2023-%02d", 1:10),
#'     location_code = "nation",
#'     age = "total"
#'   ),
#'   id_cols = c("location_code", "age"),
#'   draws = list(numerator_nowcasted = matrix(rpois(2000, 20 + 3 * 1:10), 10))
#' )
#' ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)
#' names(ens$draws)
#'
#' # the share of draws with a positive slope; the first 4 weeks have no window
#' ens$data[, .(isoyearweek, numerator_nowcasted_trend_increasing_pr)]
#'
#' @rdname short_term_trend
#' @export
short_term_trend <- function(
  x,
  ...
) {
  UseMethod("short_term_trend", x)
}

#' @method short_term_trend csfmt_rts_data_v1
#' @rdname short_term_trend
#' @section The csfmt_rts_data_v1 table method:
#' `short_term_trend.csfmt_rts_data_v1()` is supported for counts without
#' delayed reporting. It gives each week a status from a quasi-Poisson test on
#' the slope. [short_term_trend_sts_v1()] runs the same test on a
#' `surveillance::sts` object.
#'
#' For counts with delayed reporting, run the ensemble method on the nowcast,
#' before [ens_collapse()]:
#'
#' \preformatted{
#' ens <- nowcast_delay_ecdf_v1(triangle, max_delay_days = 35)
#' ens <- short_term_trend(ens, measure = "numerator_nowcasted")
#' out <- ens_collapse(ens, heal = TRUE)
#' }
#'
#' **The ensemble method is not a drop-in.** The v1 method takes `numerator`,
#' `denominator`, `prX` and the `*_naming_prefix` arguments. The ensemble method
#' takes one draw matrix, `measure`. The v1 method returns a status and a
#' doubling time from a quasi-Poisson log-link fit. The ensemble method returns a
#' slope, a growth rate and the share of draws with a positive slope. So the call
#' changes, and the numbers do not match.
#'
#' The v1 method needs `granularity_time == "isoyearweek"`. A window is
#' `increasing` when its slope is positive with a p-value at most `alpha`.
#' @param numerator The count column.
#' @param prX The scale of the rate `numerator / denominator`, such as `100`. It
#'   MAY hold more than one scale.
#' @param remove_last_isoyearweeks The number of latest weeks to leave out of the
#'   fit. They get the status `"forecast"`.
#' @param forecast_isoyearweeks The number of weeks to forecast after the data.
#' @param numerator_naming_prefix The start of the new column names.
#'   `"from_numerator"` is the numerator name without its last `_<word>`, and
#'   `"generic"` is `"numerator"`. Any other string is used as written.
#' @param denominator_naming_prefix The same for the denominator.
#' @param statistics_naming_prefix `"universal"` names the columns
#'   `<prefix>_trend0_<days>_status` and `<prefix>_doublingdays0_<days>`, with
#'   `<days> = 7 * trend_isoyearweeks - 1`. `"from_numerator_and_prX"` adds the
#'   numerator suffix, or `_pr<prX>` with a denominator.
#' @param remove_training_data If `TRUE`, drop the first `trend_isoyearweeks - 1`
#'   rows, which have no window.
#' @param include_decreasing If `FALSE`, the levels are `"training"`,
#'   `"forecast"`, `"notincreasing"` and `"increasing"`. If `TRUE`, they are
#'   `"training"`, `"forecast"`, `"decreasing"`, `"null"` and `"increasing"`.
#' @param alpha The significance level of the test on the slope.
#' @returns The v1 method returns `x` with the forecast weeks added. The new
#'   columns are the status, the doubling time in days, the forecast with its
#'   2.5% and 97.5% limits, and a logical forecast marker. With a denominator,
#'   it also adds the forecast denominator and rates.
#' @examples
#' # the csfmt_rts_data_v1 table method, for counts without delayed reporting
#' d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
#' d <- d[granularity_time=="isoyearweek"]
#' res <- csalert::short_term_trend(
#'   d,
#'   numerator = "hospitalization_with_covid19_as_primary_cause_n",
#'   trend_isoyearweeks = 6
#' )
#' print(res[, .(
#'   isoyearweek,
#'   hospitalization_with_covid19_as_primary_cause_n,
#'   hospitalization_with_covid19_as_primary_cause_trend0_41_status
#' )])
#' @export
short_term_trend.csfmt_rts_data_v1 <- function(
  x,
  numerator,
  denominator = NULL,
  prX = 100,
  trend_isoyearweeks = 6,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = trend_isoyearweeks,
  numerator_naming_prefix = "from_numerator",
  denominator_naming_prefix = "from_denominator",
  statistics_naming_prefix = "universal",
  remove_training_data = FALSE,
  include_decreasing = FALSE,
  alpha = 0.05,
  ...
) {
  time_series_id <- NULL
  to_be_forecasted <- NULL

  if (!"time_series_id" %in% names(x)) {
    on.exit({
      x[, time_series_id := NULL]
    })
    remove_time_series_id <- TRUE
  } else {
    remove_time_series_id <- FALSE
  }

  stopifnot(
    statistics_naming_prefix %in% c("universal", "from_numerator_and_prX")
  )

  num_unique_ts <- cstidy::unique_time_series(x, set_time_series_id = TRUE) |>
    nrow()

  if (num_unique_ts > 1) {
    ds <- split(x, x$time_series_id)
    retval <- lapply(ds, function(y) {
      y[, time_series_id := NULL]
      return(short_term_trend_internal(
        y,
        numerator = numerator,
        denominator = denominator,
        prX = prX,
        trend_isoyearweeks = trend_isoyearweeks,
        remove_last_isoyearweeks = remove_last_isoyearweeks,
        forecast_isoyearweeks = forecast_isoyearweeks,
        numerator_naming_prefix = numerator_naming_prefix,
        denominator_naming_prefix = denominator_naming_prefix,
        statistics_naming_prefix = statistics_naming_prefix,
        remove_training_data = remove_training_data,
        include_decreasing = include_decreasing,
        alpha = alpha
      ))
    })
    retval <- rbindlist(retval) #unlist(retval, recursive = FALSE, use.names = FALSE)
  } else {
    retval <- short_term_trend_internal(
      x,
      numerator = numerator,
      denominator = denominator,
      prX = prX,
      trend_isoyearweeks = trend_isoyearweeks,
      remove_last_isoyearweeks = remove_last_isoyearweeks,
      forecast_isoyearweeks = forecast_isoyearweeks,
      numerator_naming_prefix = numerator_naming_prefix,
      denominator_naming_prefix = denominator_naming_prefix,
      statistics_naming_prefix = statistics_naming_prefix,
      remove_training_data = remove_training_data,
      include_decreasing = include_decreasing,
      alpha = alpha
    )
  }

  if (remove_time_series_id && "time_series_id" %in% names(retval)) {
    retval[, time_series_id := NULL]
  }

  cstidy::set_csfmt_rts_data_v1(retval)

  data.table::shouldPrint(retval)

  return(retval)
}

#' @method short_term_trend csfmt_rts_data_v3
#' @rdname short_term_trend
#' @returns The `csfmt_rts_data_v3` method always stops with an error.
#' @section Why the csfmt_rts_data_v3 method is an error:
#' A `csfmt_rts_data_v3` is the collapsed output of the pipeline. It holds
#' quantiles, not draws, so no per-draw trend can come from it. Run the trend
#' before the collapse:
#'
#' \preformatted{
#' ens <- short_term_trend(ens, measure = "numerator_nowcasted")  # before
#' out <- ens_collapse(ens, heal = TRUE)                          # then collapse
#' }
#' @export
short_term_trend.csfmt_rts_data_v3 <- function(x, ...) {
  stop(
    "short_term_trend() does not accept a csfmt_rts_data_v3.\n",
    "  A collapsed table is terminal output: it holds quantiles, not draws, so a\n",
    "  per-draw trend and P(increasing) cannot be recovered from it.\n",
    "  Run short_term_trend() on the csfmt_ensemble_v3, BEFORE ens_collapse():\n",
    "    ens <- short_term_trend(ens, measure = \"numerator_nowcasted\")\n",
    "    out <- ens_collapse(ens, heal = TRUE)",
    call. = FALSE
  )
}
