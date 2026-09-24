gen_data_short_term_trend <- function(seed = 4) {
  isoyear <- NULL
  cases_n <- NULL
  seasonweek <- NULL

  d <- cstidy::csfmt_rts_data_v1(data.table(
    location_code = "norge",
    date = do.call(c, cstime::dates_by_isoyearweek[isoyear == 2020]$days),
    age = "total",
    sex = "total",
    border = 2020
  ))
  # set.seed(4)
  d[, cases_n := stats::rpois(.N, lambda = seasonweek * 4)]
  return(d)
}

# x = d_msis[granularity_geo=="nation" & granularity_time=="isoyearweek"]
# numerator = "covid19_cases_testdate_n"
# trend_isoyearweeks = 6
# remove_last_isoyearweeks = 1

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

# One window's status from its slope and p-value. Without
# `include_decreasing` the test is one-sided: a significant negative slope is
# "notincreasing", the same label a flat series gets.
stt_v1_status <- function(pval, co, alpha, include_decreasing) {
  if (!include_decreasing) {
    if (pval <= alpha && co > 0) {
      return("increasing")
    }
    return("notincreasing")
  }
  if (pval > alpha) {
    return("null")
  }
  if (co < 0) {
    return("decreasing")
  }
  return("increasing")
}

# Fit one quasi-Poisson GLM per rolling window and label its status.
#
# `model` and `model_denominator` are the fits from the LAST window, and the
# caller uses them to build the forecast. A window that warns or errors leaves
# them NULL, which is what the caller tests for.
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
  trend_variable <- NULL
  model <- NULL
  model_denominator <- NULL
  for (i in seq_len(nrow(x) - remove_last_rows)) {
    index <- (i - trend_rows + 1):i
    if (min(index) < 1) {
      next()
    }

    training_data <- with_pred[index]

    formula <- glue::glue("{varname_forecast_numerator} ~ trend_variable")

    # model for data with denom
    model_denominator <- NULL
    if (!is.null(denominator)) {
      # if denominator is zero, replace with 1
      training_data[
        get(varname_forecast_denominator) == 0,
        (varname_forecast_denominator) := 1
      ]

      formula_denominator <- glue::glue(
        "{varname_forecast_denominator} ~ trend_variable"
      )
      tryCatch(
        {
          # qp model
          model_denominator <- glm2::glm2(
            stats::as.formula(formula_denominator),
            data = training_data,
            family = stats::quasipoisson(link = "log")
          )
        },
        warning = function(cond) {
          return(model_denominator <- NULL)
        },
        error = function(cond) {
          return(model_denominator <- NULL)
        }
      )

      formula <- glue::glue(
        "{formula} + offset(log({varname_forecast_denominator}))"
      )
    }

    # model for data with num only
    model <- NULL
    tryCatch(
      {
        model <- glm2::glm2(
          stats::as.formula(formula),
          data = training_data,
          family = stats::quasipoisson(link = "log")
        )

        # determine the trend based on beta
        vals <- stats::coef(summary(model))
        co <- vals["trend_variable", "Estimate"]
        pval <- vals["trend_variable", ][[4]]
        trend[i] <- stt_v1_status(pval, co, alpha, include_decreasing)
        doubling_time[i] <- nrow(with_pred) * log(2) / co # remember to scale it so that it is per date!!
        if (gran_time == "isoyearweek") {
          doubling_time[i] <- doubling_time[i] * 7 # remember to scale it so that it is per date!!
        }
      },
      warning = function(cond) {
        return(model <- NULL)
      },
      error = function(cond) {
        return(model <- NULL)
      }
    )
  }
  return(list(
    trend = trend,
    doubling_time = doubling_time,
    model = model,
    model_denominator = model_denominator
  ))
}


# Write the forecast and its prediction interval into `with_pred`, by
# reference. A missing fit blanks every forecast column instead of leaving the
# training values in place.
stt_v1_forecast <- function(
  with_pred,
  model,
  model_denominator,
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
  if (is.null(model) || (!is.null(denominator) && is.null(model_denominator))) {
    suppressWarnings(with_pred[
      to_be_forecasted == TRUE,
      (varname_forecast_denominator) := NA_real_
    ])
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
    if (!is.null(denominator)) {
      forecasted_denominator <- prediction_interval(
        model_denominator,
        with_pred[to_be_forecasted == TRUE],
        alpha = 0.05
      )
      suppressWarnings(with_pred[
        to_be_forecasted == TRUE,
        (varname_forecast_denominator) := round(forecasted_denominator$point)
      ])
      # if denominator is zero, replace with 1
      with_pred[
        to_be_forecasted == TRUE & get(varname_forecast_denominator) == 0,
        (varname_forecast_denominator) := 1
      ]
    }

    forecasted <- prediction_interval(
      model,
      with_pred[to_be_forecasted == TRUE],
      alpha = 0.05
    )
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

  #if(remove_last_dates > 0) indexes <- indexes[-c(1:remove_last_dates)]
  #indexes <- indexes[which(cstime::keep_sundates_and_latest_date(x$date[indexes]) != "delete")]
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
  model <- fitted$model
  model_denominator <- fitted$model_denominator
  trend <- factor(trend, levels = stt_v1_status_levels(include_decreasing))
  stt_v1_forecast(
    with_pred,
    model,
    model_denominator,
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
#' every draw. The deprecated `csfmt_rts_data_v1` method fits a rolling
#' quasi-Poisson regression to a table, after Benedetti (2019)
#' <doi:10.5588/pha.19.0002>.
#' @param x A `csfmt_ensemble_v3`, or a deprecated `csfmt_rts_data_v1`.
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
#' @section The deprecated csfmt_rts_data_v1 method:
#' `short_term_trend.csfmt_rts_data_v1()` is **deprecated**. It still works and
#' gives no warning. New work SHOULD run the ensemble method before
#' [ens_collapse()]:
#'
#' \preformatted{
#' ens <- nowcast_delay_ecdf_v1(triangle, max_delay_days = 35)
#' ens <- short_term_trend(ens, measure = "numerator_nowcasted")
#' out <- ens_collapse(ens, heal = TRUE)
#' }
#'
#' **The replacement is not a drop-in.** The v1 method takes `numerator`,
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
#' # the deprecated csfmt_rts_data_v1 method
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
