gen_data_signal_detection_hlm <- function(seed = 4){

  isoyear <- NULL
  cases_n <- NULL
  seasonweek <- NULL


  d <- cstidy::csfmt_rts_data_v1(data.table(
    granularity_time = "isoyearweek",
    location_code = "norge",
    isoyearweek = cstime::dates_by_isoyearweek[isoyear %in% c(2015:2023)]$isoyearweek,
    age = "total",
    sex = "total",
    border = 2020
  ))
  # set.seed(4)
  d[, cases_n := stats::rpois(.N, lambda = seasonweek*4)]
  shouldPrint(d)
  return(d)
}

#' Detect signals using the historical limits method
#'
#' @description
#' Flags weeks where the observed value is unusually high compared with a baseline
#' built from the same weeks in previous years. For each week, a baseline mean and
#' standard deviation are computed from the surrounding weeks
#' (\code{week - 1}, \code{week}, \code{week + 1}) in each of the previous
#' \code{baseline_isoyears} years. A week is flagged as \code{"high"} when its
#' value exceeds the upper (99.5\%) baseline prediction interval.
#'
#' @param x Data object.
#' @param ... Not in use.
#' @rdname signal_detection_hlm
#' @export
signal_detection_hlm <- function(
  x,
 ...
){
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
#' @param value Character of name of value
#' @param baseline_isoyears Number of years in the past you want to include as baseline
#' @param remove_last_isoyearweeks Number of isoyearweeks you want to remove at the end (due to unreliable data)
#' @param forecast_isoyearweeks Number of isoyearweeks you want to forecast into the future
#' @param value_naming_prefix "from_numerator", "generic", or a custom prefix
#' @param remove_training_data Boolean. If TRUE, removes the training data (i.e. the early weeks that have no baseline) from the returned dataset.
#' @param ... Not in use.
#' @returns The original csfmt_rts_data_v1 dataset with extra columns. \code{*_status} is a factor with levels c("training", "forecast", "null", "high") flagging weeks above the baseline, \code{*_forecasted*} holds the observed value (or the baseline median for forecast weeks), and \code{*_baseline_predinterval_*} holds the lower (0.5\%), median (50\%) and upper (99.5\%) baseline prediction interval.
#' @examples
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
  ){

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


  if(!"time_series_id" %in% names(x)){
    remove_time_series_id <- TRUE
  } else {
    remove_time_series_id <- FALSE
  }

  x <- copy(x)
  num_unique_ts <- cstidy::unique_time_series(x, set_time_series_id = TRUE) %>%
    nrow()

  to_be_forecasted <- NULL
  trend_variable <- NULL

  # check granularity time. can only do date and isoyearweek
  gran_time <- x$granularity_time[1]
  if(!gran_time %in% c("isoyearweek")){
    stop("granularity_time is not isoyearweek")
  }

  max_isoyearweek <- max(x$isoyearweek)

  remove_last_rows <- remove_last_isoyearweeks
  forecast_rows <- forecast_isoyearweeks

  if(forecast_isoyearweeks > 0){
    with_pred <- cstidy::expand_time_to(x, max_isoyearweek = cstime::date_to_isoyearweek_c(max(x$date)+forecast_isoyearweeks*7))
  } else {
    with_pred <- copy(x)
  }

  # numerator name
  suffix <- stringr::str_extract(value, "_[a-z0-9]+$")
  if(value_naming_prefix=="from_numerator"){
    prefix <- stringr::str_remove(value, "_[a-z0-9]+$")
  } else if(value_naming_prefix=="generic") {
    prefix <- "value"
  } else {
    prefix <- value_naming_prefix
  }

  # create forecast var names (num, denom)
  varname_forecast_value <- paste0(prefix, "_forecasted", suffix)
  varname_forecast <- paste0(varname_forecast_value, "_forecast")
  varname_baseline_predinterval_q50x0_value <- paste0(prefix, "_baseline_predinterval_q50x0", suffix)
  varname_baseline_predinterval_q00x5_value <- paste0(prefix, "_baseline_predinterval_q00x5", suffix)
  varname_baseline_predinterval_q99x5_value <- paste0(prefix, "_baseline_predinterval_q99x5", suffix)


  varname_status <- paste0(value, "_status")

  # training/forecast period
  with_pred[, to_be_forecasted := isoyearweek > max_isoyearweek]

  baseline <- expand.grid(
    weeks = -1:1,
    years = 1:baseline_isoyears
  ) %>%
    setDT()
  baseline[, lag := years*52 + weeks]
  baseline[, var := paste0("d", 1:.N)]

  for(i in 1:nrow(baseline)){
    with_pred[, (baseline$var[i]) := shift(get(value), n = baseline$lag[i]), by = .(time_series_id)]
  }
  with_pred[, baseline_mean := row_mean(.SD), .SDcols = baseline$var]
  with_pred[, baseline_sd := row_sd(.SD), .SDcols = baseline$var]

  # dont assign floats to integer columns
  if(suffix=="_n"){
    fn <- round
  } else {
    fn <- function(x) return(x)
  }
  with_pred[to_be_forecasted==FALSE , (varname_forecast_value) := get(value)]
  with_pred[,(varname_forecast) := to_be_forecasted]
  with_pred[, (varname_baseline_predinterval_q50x0_value) := fn(stats::qnorm(0.50, baseline_mean, baseline_sd))]
  with_pred[to_be_forecasted==TRUE, (varname_forecast_value) := get(varname_baseline_predinterval_q50x0_value)]
  with_pred[, (varname_baseline_predinterval_q00x5_value) := fn(stats::qnorm(0.005, baseline_mean, baseline_sd))]
  with_pred[, (varname_baseline_predinterval_q99x5_value) := fn(stats::qnorm(0.995, baseline_mean, baseline_sd))]

  with_pred[, (varname_status) := "null"]
  with_pred[get(value) > get(varname_baseline_predinterval_q99x5_value), (varname_status) := "high"]
  with_pred[is.na(baseline_mean), (varname_status) := "training"]
  with_pred[to_be_forecasted==TRUE, (varname_status) := "forecast"]
  with_pred[, (varname_status) := factor(
    get(varname_status),
    levels = c("training", "forecast", "null", "high")
  )]

  for(i in 1:nrow(baseline)){
    with_pred[, (baseline$var[i]) := NULL]
  }
  with_pred[, baseline_mean := NULL]
  with_pred[, baseline_sd := NULL]
  with_pred[, to_be_forecasted := NULL]

  if(remove_training_data) with_pred <- with_pred[get(varname_status) != "training"]


  if(remove_time_series_id & "time_series_id" %in% names(with_pred)) with_pred[, time_series_id := NULL]

  cstidy::set_csfmt_rts_data_v1(with_pred)

  data.table::shouldPrint(with_pred)

  return(with_pred)
}
