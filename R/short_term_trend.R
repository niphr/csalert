gen_data_short_term_trend <- function(seed = 4){

  isoyear <- NULL
  cases_n <- NULL
  seasonweek <- NULL


  d <- cstidy::csfmt_rts_data_v1(data.table(
    location_code = "norge",
    date = do.call(c, cstime::dates_by_isoyearweek[isoyear==2020]$days),
    age = "total",
    sex = "total",
    border = 2020
  ))
  # set.seed(4)
  d[, cases_n := stats::rpois(.N, lambda = seasonweek*4)]
  return(d)
}

# x = d_msis[granularity_geo=="nation" & granularity_time=="isoyearweek"]
# numerator = "covid19_cases_testdate_n"
# trend_isoyearweeks = 6
# remove_last_isoyearweeks = 1

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
  ){


  to_be_forecasted <- NULL
  trend_variable <- NULL

  # check number of ts. can only process 1 for now
  num_unique_ts <- cstidy::unique_time_series(x) %>%
    nrow()
  if(num_unique_ts>1){
    stop("There is more than 1 time series in this dataset")
  }

  # check granularity time. can only do date and isoyearweek
  gran_time <- x$granularity_time[1]
  if(!gran_time %in% c("isoyearweek")){
    stop("granularity_time is not isoyearweek")
  }

  # weekly vs daily
  # create with_pred

  # must have more than 2 weeks data
  if(trend_isoyearweeks < 2){
    stop("trend_isoyearweeks must be >= 2 when granularity_time is isoyearweek")
  }
  trend_rows <- trend_isoyearweeks
  remove_last_rows <- remove_last_isoyearweeks
  forecast_rows <- forecast_isoyearweeks

  trend_dates <- trend_isoyearweeks * 7 - 1
  # ??
  with_pred <- cstidy::expand_time_to(x, max_isoyearweek = cstime::date_to_isoyearweek_c(max(x$date)+forecast_isoyearweeks*7))

  # numerator name
  suffix <- stringr::str_extract(numerator, "_[a-z]+$")
  if(numerator_naming_prefix=="from_numerator"){
    prefix <- stringr::str_remove(numerator, "_[a-z]+$")
  } else if(numerator_naming_prefix=="generic") {
    prefix <- "numerator"
  } else {
    prefix <- numerator_naming_prefix
  }

  # denom
  if(denominator_naming_prefix=="from_denominator"){
    prefix_denom <- stringr::str_remove(denominator, "_[a-z]+$")
  } else if(denominator_naming_prefix=="generic") {
    prefix_denom <- "denominator"
  } else {
    prefix_denom <- denominator_naming_prefix
  }

  prefix_pr100 <- paste0(prefix,"_vs_", prefix_denom)

  # create forecast var names (num, denom)
  varname_forecast_numerator <- paste0(prefix, "_forecasted", suffix)
  varname_forecast_predinterval_q02x5_numerator <- paste0(prefix, "_forecasted_predinterval_q02x5", suffix)
  varname_forecast_predinterval_q97x5_numerator <- paste0(prefix, "_forecasted_predinterval_q97x5", suffix)
  varname_forecast_numerator <- paste0(prefix, "_forecasted", suffix)
  if(!is.null(denominator)){
    varname_forecast_denominator <- paste0(prefix_denom, "_forecasted", suffix)

    varname_forecast_prX <- paste0(prefix_pr100, "_forecasted_pr", formatC(prX, format="f", digits = 0))
    varname_forecast_prX_is_forecast <- paste0(prefix_pr100, "_forecasted_pr", formatC(prX, format="f", digits = 0),"_forecast")
    varname_forecast_predinterval_q02x5_prX <- paste0(prefix_pr100, "_forecasted_predinterval_q02x5_pr", formatC(prX, format="f", digits = 0))
    varname_forecast_predinterval_q97x5_prX <- paste0(prefix_pr100, "_forecasted_predinterval_q97x5_pr", formatC(prX, format="f", digits = 0))

    if(statistics_naming_prefix=="universal"){
      varname_trend <- paste0(prefix_pr100, "_trend0_",trend_dates, "_status")
      varname_dates_to_double <- paste0(prefix_pr100, "_doublingdays0_",trend_dates)
    } else {
      varname_trend <- paste0(prefix_pr100, "_trend0_",trend_dates, "_pr", formatC(prX, format="f", digits = 0), "_status")
      varname_dates_to_double <- paste0(prefix_pr100, "_doublingdays0_",trend_dates, "_pr", formatC(prX, format="f", digits = 0))
    }

    varname_forecast <- c(
      paste0(varname_forecast_numerator, "_forecast"),
      paste0(varname_forecast_prX, "_forecast")
    )
  } else {
    if(statistics_naming_prefix=="universal"){
      varname_trend <- paste0(prefix, "_trend0_",trend_dates, "_status")
      varname_dates_to_double <- paste0(prefix, "_doublingdays0_",trend_dates)
    } else {
      varname_trend <- paste0(prefix, "_trend0_",trend_dates, suffix, "_status")
      varname_dates_to_double <- paste0(prefix, "_doublingdays0_",trend_dates, suffix)
    }

    varname_forecast <- paste0(varname_forecast_numerator, "_forecast")
  }


  # training/forecast period
  with_pred[, to_be_forecasted := FALSE]
  with_pred[(.N-remove_last_rows-forecast_rows+1):.N, to_be_forecasted := TRUE]

  with_pred[ , (varname_forecast_numerator) := get(numerator)]
  if(!is.null(denominator)) with_pred[, (varname_forecast_denominator) := get(denominator)]
  with_pred[, trend_variable := 1:.N / .N]

  doubling_time <- rep(NA_real_, nrow(with_pred))

  # trend
  # training period
  trend <- rep(NA_character_, nrow(with_pred))
  trend[1:(trend_rows-1)] <- "training"
  trend[(length(trend)-remove_last_rows-forecast_rows+1):length(trend)] <- "forecast"

  #if(remove_last_dates > 0) indexes <- indexes[-c(1:remove_last_dates)]
  #indexes <- indexes[which(cstime::keep_sundates_and_latest_date(x$date[indexes]) != "delete")]
  for(i in seq_len(nrow(x)-remove_last_rows)){
    index <- (i - trend_rows + 1):i
    if(min(index) < 1){
      next()
    }

    training_data <- with_pred[index]

    formula <- glue::glue("{varname_forecast_numerator} ~ trend_variable")

    # model for data with denom
    model_denominator <- NULL
    if(!is.null(denominator)){
      # if denominator is zero, replace with 1
      training_data[get(varname_forecast_denominator)==0, (varname_forecast_denominator) := 1]

      formula_denominator <- glue::glue("{varname_forecast_denominator} ~ trend_variable")
      tryCatch({
        # qp model
        model_denominator <- glm2::glm2(
          stats::as.formula(formula_denominator),
          data = training_data,
          family = stats::quasipoisson(link = "log")
        )
      },
      warning = function(cond){
        model_denominator <- NULL
      },
      error = function(cond){
        model_denominator <- NULL
      })

      formula <- glue::glue("{formula} + offset(log({varname_forecast_denominator}))")
    }

    # model for data with num only
    model <- NULL
    tryCatch({
      model <- glm2::glm2(
        stats::as.formula(formula),
        data = training_data,
        family = stats::quasipoisson(link = "log")
      )

      # determine the trend based on beta
      vals <- stats::coef(summary(model))
      co <- vals["trend_variable", "Estimate"]
      pval <- vals["trend_variable",][[4]]
      if(include_decreasing){
        if(pval > alpha){
          trend[i] <- "null"
        } else {
          if(co < 0){
            trend[i] <- "decreasing"
          } else{
            trend[i] <- "increasing"
          }
        }
      } else {
        if(pval <= alpha & co > 0){
          trend[i] <- "increasing"
        } else {
          trend[i] <- "notincreasing"
        }
      }
      doubling_time[i] <- nrow(with_pred)*log(2)/co # remember to scale it so that it is per date!!
      if(gran_time=="isoyearweek"){
        doubling_time[i] <- doubling_time[i]*7 # remember to scale it so that it is per date!!
      }
    },
    warning = function(cond){
      model <- NULL
    },
    error = function(cond){
      model <- NULL
    })
  }
  if(include_decreasing){
    trend <- factor(trend, levels = c("training", "forecast", "decreasing", "null", "increasing"))
  } else {
    trend <- factor(trend, levels = c("training", "forecast", "notincreasing", "increasing"))
  }
  # prediction interval
  if(is.null(model) | (!is.null(denominator) & is.null(model_denominator))){
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_denominator) := NA_real_])
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_numerator) := NA_real_])
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_predinterval_q02x5_numerator) := NA_real_])
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_predinterval_q97x5_numerator) := NA_real_])

    if(!is.null(denominator)){
      with_pred[, (varname_forecast_prX) := NA_real_]
      with_pred[, (varname_forecast_predinterval_q02x5_prX) := NA_real_]
      with_pred[, (varname_forecast_predinterval_q97x5_prX) := NA_real_]
    }
  } else {
    if(!is.null(denominator)){
      forecasted_denominator <- prediction_interval(model_denominator, with_pred[to_be_forecasted==TRUE], alpha = 0.05)
      suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_denominator) := round(forecasted_denominator$point)])
      # if denominator is zero, replace with 1
      with_pred[to_be_forecasted==TRUE & get(varname_forecast_denominator)==0, (varname_forecast_denominator) := 1]
    }

    forecasted <- prediction_interval(model, with_pred[to_be_forecasted==TRUE], alpha = 0.05)
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_numerator) := round(forecasted$point)])
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_predinterval_q02x5_numerator) := round(forecasted$lower)])
    suppressWarnings(with_pred[to_be_forecasted==TRUE, (varname_forecast_predinterval_q97x5_numerator) := round(forecasted$upper)])

    if(!is.null(denominator)){
      # if numerator is predicted to be bigger than denominator, set numerator to denominator
      # todo: this probably should be fixed
      with_pred[get(varname_forecast_numerator) > get(varname_forecast_denominator), (varname_forecast_numerator) := get(varname_forecast_denominator)]

      for(i in seq_along(prX)){
        with_pred[, (varname_forecast_prX[i]) := prX[i] * get(varname_forecast_numerator) / get(varname_forecast_denominator)]
        with_pred[is.nan(get(varname_forecast_prX[i])), (varname_forecast_prX[i]) := 0]

        with_pred[, (varname_forecast_predinterval_q02x5_prX[i]) := prX[i] * get(varname_forecast_predinterval_q02x5_numerator) / get(varname_forecast_denominator)]
        with_pred[is.nan(get(varname_forecast_predinterval_q02x5_prX[i])), (varname_forecast_predinterval_q02x5_prX[i]) := 0]

        with_pred[, (varname_forecast_predinterval_q97x5_prX[i]) := prX[i] * get(varname_forecast_predinterval_q97x5_numerator) / get(varname_forecast_denominator)]
        with_pred[is.nan(get(varname_forecast_predinterval_q97x5_prX[i])), (varname_forecast_predinterval_q97x5_prX[i]) := 0]
      }
    }
  }

  with_pred[, trend_variable := NULL]
  for(i in varname_forecast){
    with_pred[, (i) := to_be_forecasted]
  }
  with_pred[, to_be_forecasted := NULL]

  with_pred[, (varname_trend) := trend]
  with_pred[, (varname_dates_to_double) := round(doubling_time,1)]

  if(remove_training_data) with_pred <- with_pred[-(1:(trend_rows-1))]

  return(with_pred)
}

#' Determine the short term trend of a timeseries
#'
#' @description
#' Fits a quasi-Poisson regression over a moving window of recent weeks and
#' classifies the short-term trend of the numerator (optionally per a
#' denominator) as increasing or not, together with an estimated doubling time.
#' The method is based upon a published analytics strategy by Benedetti (2019)
#' <doi:10.5588/pha.19.0002>.
#' @param x Data object
#' @param ... Not in use.
#' @rdname short_term_trend
#' @export
short_term_trend <- function(
  x,
 ...
){
  UseMethod("short_term_trend", x)
}

#' @method short_term_trend csfmt_rts_data_v1
#' @rdname short_term_trend
#' @param numerator Character of name of numerator
#' @param denominator Character of name of denominator (optional)
#' @param prX If using denominator, what scaling factor should be used for numerator/denominator?
#' @param trend_isoyearweeks Same as trend_dates, but used if granularity_geo=='isoyearweek'
#' @param remove_last_isoyearweeks Same as remove_last_dates, but used if granularity_geo=='isoyearweek'
#' @param forecast_isoyearweeks Same as forecast_dates, but used if granularity_geo=='isoyearweek'
#' @param numerator_naming_prefix "from_numerator", "generic", or a custom prefix
#' @param denominator_naming_prefix "from_denominator", "generic", or a custom prefix
#' @param statistics_naming_prefix "universal" (one variable for trend status, one variable for doubling dates), "from_numerator_and_prX" (If denominator is NULL, then one variable corresponding to numerator. If denominator exists, then one variable for each of the prXs)
#' @param remove_training_data Boolean. If TRUE, removes the training data (i.e. 1:(trend_dates-1) or 1:(trend_isoyearweeks-1)) from the returned dataset.
#' @param include_decreasing If true, then *_trend*_status contains the levels c("training", "forecast", "decreasing", "null", "increasing"), otherwise the levels c("training", "forecast", "notincreasing", "increasing").
#' @param alpha Significance level for change in trend.
#' @param ... Not in use.
#' @returns The original csfmt_rts_data_v1 dataset with extra columns. *_trend*_status contains a factor with levels c("training", "forecast", "decreasing", "null", "increasing"), while *_doublingdays* contains the expected number of days before the numerator doubles.
#' @examples
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
  ){

  time_series_id <- NULL
  to_be_forecasted <- NULL


  if(!"time_series_id" %in% names(x)){
    on.exit({
      x[, time_series_id := NULL]
    })
    remove_time_series_id <- TRUE
  } else {
    remove_time_series_id <- FALSE
  }

  stopifnot(statistics_naming_prefix %in% c("universal", "from_numerator_and_prX"))

  num_unique_ts <- cstidy::unique_time_series(x, set_time_series_id = TRUE) %>%
    nrow()

  if(num_unique_ts > 1){
    ds <- split(x, x$time_series_id)
    retval <- lapply(ds, function(y){
      y[, time_series_id := NULL]
      short_term_trend_internal(
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
      )
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

  if(remove_time_series_id & "time_series_id" %in% names(retval)) retval[, time_series_id := NULL]

  cstidy::set_csfmt_rts_data_v1(retval)

  data.table::shouldPrint(retval)

  return(retval)
}
