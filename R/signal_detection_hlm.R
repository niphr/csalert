gen_data_signal_detection_hlm <- function(seed = 4) {
  isoyear <- NULL
  cases_n <- NULL
  seasonweek <- NULL

  d <- cstidy::csfmt_rts_data_v1(data.table(
    granularity_time = "isoyearweek",
    location_code = "norge",
    isoyearweek = cstime::dates_by_isoyearweek[
      isoyear %in% c(2015:2023)
    ]$isoyearweek,
    age = "total",
    sex = "total",
    border = 2020
  ))
  # set.seed(4)
  d[, cases_n := stats::rpois(.N, lambda = seasonweek * 4)]
  shouldPrint(d)
  return(d)
}

#' Flag weeks above a historical limit
#'
#' @description
#' Flags a week as `high` above the historical limit, the 99.5% quantile of a
#' normal fitted to the same weeks in earlier years. The ensemble
#' method compares every draw with the limit.
#'
#' @details
#' The baseline of a week is the values 52, 104, and so on up to
#' `52 * baseline_isoyears` rows back, each with its two neighbours. The limit is
#' `qnorm(0.995, mean, sd)` of those values. A week that lacks any of them gets
#' none. A year back is 52 rows, so across a 53-week ISO year the baseline is
#' one week off. The limit is treated as known.
#' @param x A `csfmt_ensemble_v3`, or a deprecated `csfmt_rts_data_v1`.
#' @param ... Passed to the method.
#' @family ensemble operations
#' @seealso `vignette("pipeline", package = "csalert")`, stage 7, and
#'   `vignette("csalert", package = "csalert")` on which method to use.
#' @rdname signal_detection_hlm
#' @export
signal_detection_hlm <- function(
  x,
  ...
) {
  UseMethod("signal_detection_hlm", x)
}

# x = gen_data_signal_detection_hlm()
# value = "cases_n"
# baseline_isoyears = 5
# remove_last_isoyearweeks = 1
# forecast_isoyearweeks = 1
# value_naming_prefix = "from_numerator"
# statistics_naming_prefix = "universal"
# remove_training_data = FALSE

#' @method signal_detection_hlm csfmt_rts_data_v1
#' @rdname signal_detection_hlm
#' @section The deprecated csfmt_rts_data_v1 method:
#' `signal_detection_hlm.csfmt_rts_data_v1()` is **deprecated**. It still works
#' and gives no warning. New work SHOULD run the ensemble method before
#' [ens_collapse()]:
#'
#' \preformatted{
#' ens <- nowcast_delay_ecdf_v1(triangle, max_delay_days = 35)
#' ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")
#' out <- ens_collapse(ens, heal = TRUE)
#' }
#'
#' **The replacement is not a drop-in.** The v1 method takes `value`,
#' `remove_last_isoyearweeks`, `forecast_isoyearweeks` and `value_naming_prefix`,
#' where the ensemble method takes a draw matrix, `measure`. The v1 method returns
#' a label per week. The ensemble method classifies every draw, so after the
#' collapse it gives the share of draws above the limit.
#'
#' The v1 method labels a week `high` when its value is above the limit, and
#' `training` when it has no baseline.
#' @param value The value column.
#' @param baseline_isoyears The number of earlier years in the baseline.
#' @param remove_last_isoyearweeks It has no effect: the method never uses it.
#' @param forecast_isoyearweeks The number of weeks to add after the data, with
#'   the baseline median as forecast and the status `"forecast"`.
#' @param value_naming_prefix The start of the new column names:
#'   `"from_numerator"` is `value` without its last `_<word>`, `"generic"` is
#'   `"value"`, and any other string is used as written.
#' @param remove_training_data If `TRUE`, drop the `"training"` weeks.
#' @returns The v1 method returns `x` with the forecast weeks added, and:
#' * `<value>_status`, a factor with the levels `"training"`, `"forecast"`,
#'   `"null"` and `"high"`,
#' * `*_forecasted_*`, the value or the forecast, and a logical forecast marker,
#' * `*_baseline_predinterval_*`, the 0.5%, 50% and 99.5% quantiles of the
#'   baseline normal.
#' @examples
#' # the deprecated csfmt_rts_data_v1 method
#' d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
#' d <- d[granularity_time=="isoyearweek"]
#' res <- csalert::signal_detection_hlm(
#'   d,
#'   value = "hospitalization_with_covid19_as_primary_cause_n",
#'   baseline_isoyears = 1
#' )
#' print(res[, .(
#'   isoyearweek,
#'   hospitalization_with_covid19_as_primary_cause_n,
#'   hospitalization_with_covid19_as_primary_cause_forecasted_n,
#'   hospitalization_with_covid19_as_primary_cause_forecasted_n_forecast,
#'   hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q50x0_n,
#'   hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q99x5_n,
#'   hospitalization_with_covid19_as_primary_cause_n_status
#' )])
#' @export
signal_detection_hlm.csfmt_rts_data_v1 <- function(
  x,
  value,
  baseline_isoyears = 5,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = 2,
  value_naming_prefix = "from_numerator",
  remove_training_data = FALSE,
  ...
) {
  . <- NULL
  time_series_id <- NULL
  to_be_forecasted <- NULL
  isoyearweek <- NULL
  lag <- NULL
  years <- NULL
  weeks <- NULL
  var <- NULL
  baseline_mean <- NULL
  baseline_sd <- NULL

  if (!"time_series_id" %in% names(x)) {
    remove_time_series_id <- TRUE
  } else {
    remove_time_series_id <- FALSE
  }

  x <- copy(x)
  num_unique_ts <- cstidy::unique_time_series(x, set_time_series_id = TRUE) |>
    nrow()

  to_be_forecasted <- NULL
  trend_variable <- NULL

  # check granularity time. can only do date and isoyearweek
  gran_time <- x$granularity_time[1]
  if (!gran_time %in% c("isoyearweek")) {
    stop("granularity_time is not isoyearweek", call. = FALSE)
  }

  max_isoyearweek <- max(x$isoyearweek)

  remove_last_rows <- remove_last_isoyearweeks
  forecast_rows <- forecast_isoyearweeks

  if (forecast_isoyearweeks > 0) {
    with_pred <- cstidy::expand_time_to(
      x,
      max_isoyearweek = cstime::date_to_isoyearweek_c(
        max(x$date) + forecast_isoyearweeks * 7
      )
    )
  } else {
    with_pred <- copy(x)
  }

  # numerator name
  suffix <- stringr::str_extract(value, "_[a-z0-9]+$")
  if (value_naming_prefix == "from_numerator") {
    prefix <- stringr::str_remove(value, "_[a-z0-9]+$")
  } else if (value_naming_prefix == "generic") {
    prefix <- "value"
  } else {
    prefix <- value_naming_prefix
  }

  # create forecast var names (num, denom)
  varname_forecast_value <- paste0(prefix, "_forecasted", suffix)
  varname_forecast <- paste0(varname_forecast_value, "_forecast")
  varname_baseline_predinterval_q50x0_value <- paste0(
    prefix,
    "_baseline_predinterval_q50x0",
    suffix
  )
  varname_baseline_predinterval_q00x5_value <- paste0(
    prefix,
    "_baseline_predinterval_q00x5",
    suffix
  )
  varname_baseline_predinterval_q99x5_value <- paste0(
    prefix,
    "_baseline_predinterval_q99x5",
    suffix
  )

  varname_status <- paste0(value, "_status")

  # training/forecast period
  with_pred[, to_be_forecasted := isoyearweek > max_isoyearweek]

  baseline <- expand.grid(
    weeks = -1:1,
    years = 1:baseline_isoyears
  ) |>
    setDT()
  baseline[, lag := years * 52 + weeks]
  baseline[, var := paste0("d", seq_len(.N))]

  for (i in seq_len(nrow(baseline))) {
    with_pred[,
      (baseline$var[i]) := shift(get(value), n = baseline$lag[i]),
      by = .(time_series_id)
    ]
  }
  with_pred[, baseline_mean := row_mean(.SD), .SDcols = baseline$var]
  with_pred[, baseline_sd := row_sd(.SD), .SDcols = baseline$var]

  # dont assign floats to integer columns
  if (suffix == "_n") {
    fn <- round
  } else {
    fn <- function(x) return(x)
  }
  with_pred[to_be_forecasted == FALSE, (varname_forecast_value) := get(value)]
  with_pred[, (varname_forecast) := to_be_forecasted]
  with_pred[,
    (varname_baseline_predinterval_q50x0_value) := fn(stats::qnorm(
      0.50,
      baseline_mean,
      baseline_sd
    ))
  ]
  with_pred[
    to_be_forecasted == TRUE,
    (varname_forecast_value) := get(varname_baseline_predinterval_q50x0_value)
  ]
  with_pred[,
    (varname_baseline_predinterval_q00x5_value) := fn(stats::qnorm(
      0.005,
      baseline_mean,
      baseline_sd
    ))
  ]
  with_pred[,
    (varname_baseline_predinterval_q99x5_value) := fn(stats::qnorm(
      0.995,
      baseline_mean,
      baseline_sd
    ))
  ]

  with_pred[, (varname_status) := "null"]
  with_pred[
    get(value) > get(varname_baseline_predinterval_q99x5_value),
    (varname_status) := "high"
  ]
  with_pred[is.na(baseline_mean), (varname_status) := "training"]
  with_pred[to_be_forecasted == TRUE, (varname_status) := "forecast"]
  with_pred[,
    (varname_status) := factor(
      get(varname_status),
      levels = c("training", "forecast", "null", "high")
    )
  ]

  for (i in seq_len(nrow(baseline))) {
    with_pred[, (baseline$var[i]) := NULL]
  }
  with_pred[, baseline_mean := NULL]
  with_pred[, baseline_sd := NULL]
  with_pred[, to_be_forecasted := NULL]

  if (remove_training_data) {
    with_pred <- with_pred[get(varname_status) != "training"]
  }

  if (remove_time_series_id && "time_series_id" %in% names(with_pred)) {
    with_pred[, time_series_id := NULL]
  }

  cstidy::set_csfmt_rts_data_v1(with_pred)

  data.table::shouldPrint(with_pred)

  return(with_pred)
}

#' @method signal_detection_hlm csfmt_rts_data_v3
#' @rdname signal_detection_hlm
#' @returns The `csfmt_rts_data_v3` method always stops with an error.
#' @section Why the csfmt_rts_data_v3 method is an error:
#' A `csfmt_rts_data_v3` is the collapsed output of the pipeline. It holds
#' quantiles, not draws, so no per-draw comparison can come from it. Run the
#' detection before the collapse:
#'
#' \preformatted{
#' ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")  # before
#' out <- ens_collapse(ens, heal = TRUE)                              # then collapse
#' }
#' @export
signal_detection_hlm.csfmt_rts_data_v3 <- function(x, ...) {
  stop(
    "signal_detection_hlm() does not accept a csfmt_rts_data_v3.\n",
    "  A collapsed table is terminal output: it holds quantiles, not draws, so the\n",
    "  per-draw exceedance probability cannot be computed from it.\n",
    "  Run signal_detection_hlm() on the csfmt_ensemble_v3, BEFORE ens_collapse():\n",
    "    ens <- signal_detection_hlm(ens, measure = \"numerator_nowcasted\")\n",
    "    out <- ens_collapse(ens, heal = TRUE)",
    call. = FALSE
  )
}
