#' Determine the short term trend of a surveillance time series
#'
#' @description
#' Fits a quasi-Poisson regression over a moving window of recent observations of
#' a \code{surveillance} \code{sts} object and sets the alarm slot to 1 for
#' time points with a significant increasing trend (0 otherwise). The method is
#' based upon a published analytics strategy by Benedetti (2019)
#' <doi:10.5588/pha.19.0002>. This function was frozen on 2024-06-24 and operates
#' on \code{sts} objects.
#' @param sts Data object of type sts.
#' @param control Control object, a named list with several elements.
#'   \describe{
#'     \item{w}{Length of the window that is being analyzed.}
#'     \item{alpha}{Significance level for change in trend.}
#' }
#' @returns sts object with the alarms slot set to 0/1 if not-increasing/increasing.
#' @examples
#' d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
#' d <- d[granularity_time=="isoyearweek"]
#' sts <- surveillance::sts(
#'   observed = d$hospitalization_with_covid19_as_primary_cause_n, # weekly number of cases
#'   start = c(d$isoyear[1], d$isoweek[1]), # first week of the time series
#'   frequency = 52
#' )
#' x <- csalert::short_term_trend_sts_v1(
#'   sts,
#'   control = list(
#'     w = 5,
#'     alpha = 0.05
#'   )
#' )
#' plot(x)
#' @export
short_term_trend_sts_v1 <- function(
  sts,
  control = list(
    w = 5,                  # window length (behind)
    alpha = 0.05            # (one-sided) (1-alpha)% prediction interval
  )
) {
  stopifnot(inherits(sts, "sts"))

  ######################################################################
  # Use special Date class mechanism to find reference months/weeks/days
  ######################################################################

  epochAsDate <- sts@epochAsDate

  ######################################################################
  # Fetch observed and population
  ######################################################################

  # Fetch observed
  observed <- surveillance::observed(sts)
  freq <- sts@freq
  if (epochAsDate) {
    epochStr <- switch( as.character(freq), "12" = "month","52" =    "week",
                        "365" = "day")
  } else {
    epochStr <- "none"
  }

  # Fetch population
  population <- surveillance::population(sts)

  ######################################################################
  # Fix missing control options
  ######################################################################

  defaultControl <- eval(formals()$control)
  control <- utils::modifyList(defaultControl, control, keep.null = TRUE)

  ######################################################################
  # Initialize the necessary vectors
  ######################################################################
  score <- trend <- pvalue <- expected <-
    mu0Vector <- phiVector <- trendVector <-
    matrix(data = 0, nrow = length(control$range), ncol = ncol(sts))

  # Define objects
  n <- control$b*(2*control$w+1)


  # loop over columns of sts
  for (j in 1:ncol(sts)) {

    #Vector of dates
    if (epochAsDate) {
      vectorOfDates <- as.Date(sts@epoch, origin="1970-01-01")
    } else {
      vectorOfDates <- seq_len(length(observed[,j]))
    }

    # Loop over control$range
    for(k in (control$w):nrow(observed)){
      start <- k-control$w+1
      stop <- k
      obs <- observed[start:stop,j]
      pop <- population[start:stop,j]
      trend <- 1:control$w

      model <- glm2::glm2(
        obs ~ trend + log(pop),
        family = stats::quasipoisson(link = "log")
      )

      # determine the trend based on beta
      vals <- stats::coef(summary(model))
      co <- vals["trend", "Estimate"]
      pval <- vals["trend",][[4]]

      if(pval < control$alpha & co > 0){
        sts@alarm[k,j] <- 1
      } else {
        sts@alarm[k,j] <- 0
      }
    }
  }

  #Done
  return(sts)
}
