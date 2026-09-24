#' Short-term trend alarms on a surveillance sts object
#'
#' @description
#' Sets an alarm where a rolling quasi-Poisson regression finds a significant rise,
#' in each column of a `surveillance::sts` object, after Benedetti (2019)
#' <doi:10.5588/pha.19.0002>. It has not changed since 2024-06-24.
#'
#' @details
#' Each time point gets the fit of `observed ~ trend + log(population)`, by
#' `glm2::glm2()`, on the `w` time points that end there. Its alarm is 1 when the
#' slope is positive with a p-value below `alpha`, and 0 otherwise. The first
#' `w - 1` time points keep their alarm.
#' @param sts A `surveillance::sts` object.
#' @param control A list with `w`, the window width, and `alpha`, the
#'   significance level. A missing element takes its default.
#' @returns `sts` with its alarms set.
#' @family short-term trend functions
#' @seealso `vignette("csalert", package = "csalert")`, which explains the
#'   deprecated trend methods. The `csfmt_rts_data_v1` method of
#'   [short_term_trend()] is the table form of this function.
#' @examples
#' d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
#' d <- d[granularity_time=="isoyearweek"]
#' sts <- surveillance::sts(
#'   observed = d$hospitalization_with_covid19_as_primary_cause_n, # weekly counts
#'   start = c(d$isoyear[1], d$isoweek[1]), # the first week of the series
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
    w = 5, # window length (behind)
    alpha = 0.05 # (one-sided) (1-alpha)% prediction interval
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
    epochStr <- switch(
      as.character(freq),
      "12" = "month",
      "52" = "week",
      "365" = "day"
    )
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
  n <- control$b * (2 * control$w + 1)

  # loop over columns of sts
  for (j in seq_len(ncol(sts))) {
    #Vector of dates
    if (epochAsDate) {
      vectorOfDates <- as.Date(sts@epoch, origin = "1970-01-01")
    } else {
      vectorOfDates <- seq_along(observed[, j])
    }

    # Loop over control$range
    for (k in (control$w):nrow(observed)) {
      start <- k - control$w + 1
      stop <- k
      obs <- observed[start:stop, j]
      pop <- population[start:stop, j]
      trend <- 1:control$w

      model <- glm2::glm2(
        obs ~ trend + log(pop),
        family = stats::quasipoisson(link = "log")
      )

      # determine the trend based on beta
      vals <- stats::coef(summary(model))
      co <- vals["trend", "Estimate"]
      pval <- vals["trend", ][[4]]

      if (pval < control$alpha && co > 0) {
        sts@alarm[k, j] <- 1
      } else {
        sts@alarm[k, j] <- 0
      }
    }
  }

  #Done
  return(sts)
}
