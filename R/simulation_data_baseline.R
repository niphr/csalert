# gen_csfmt_rts_baseline_data <- function(start_date,
#                                          end_date){
#
#   start_date <- as.Date(start_date)
#   end_date <- as.Date(end_date)
#
#       d <- cstidy::csfmt_rts_data_v1(data.table(
#         location_code = "norge",
#         date = seq.Date(start_date,end_date,by="day"),
#         age = "total",
#         sex = "total",
#         border = 2020,
#         granularity_time="day"
#       ))
#       d[, time:=1:.N]
#
#       d[, wday:=lubridate::wday(date)]
#
#   return(d)
# }

periodic_pattern <- function(
  n_p = 2,
  g1 = 0.8,
  g2 = 0.4,
  s = 29,
  p = 52 * 7,
  t = seq_len(nrow(d))
) {
  d <- NULL

  l <- 1:n_p

  c <- rep(0, length(t))

  for (i in seq_along(t)) {
    c[i] <- sum(
      g1 *
        cos((2 * pi * l * (t[i] + s)) / (p)) +
        g2 * sin((2 * pi * l * (t[i] + s)) / (p))
    )
  }

  return(c)
}

#' Simulate daily counts with no outbreak
#'
#' @description
#' Simulates daily counts from a Poisson or negative binomial model with a trend,
#' a seasonal pattern and a day-of-week pattern, after Noufaily et al. (2019). Use
#' it to make a series with a known truth.
#'
#' @details
#' On day `t`, from 1, the log of the mean is `alpha + beta * (t + shift_1)` plus
#' a seasonal term and a weekly term. With `u = 2 * pi * (t + shift_1) / p`, each
#' term sums `a * cos(l * u) + b * sin(l * u)` over `l = 1, ..., n`:
#' * seasonal: `p = 364`, `n = seasonal_pattern_n`, `a = gamma_1`, `b = gamma_2`,
#' * weekly: `p = 7`, `n = weekly_pattern_n`, `a = gamma_3`, `b = gamma_4`.
#'
#' With both `n` at 0, the log of the mean is `alpha + beta * t`. With
#' `seasonal_pattern_n > 0`, `weekly_pattern_n = 0` still adds a weekly term,
#' because `1:0` in R is `c(1, 0)`.
#' @param start_date,end_date The first and last day, as a `Date` or a
#'   `"YYYY-MM-DD"` string.
#' @param seasonal_pattern_n The number of seasonal harmonics: 0 for none, 1 for
#'   an annual pattern, 2 to add a half-year harmonic.
#' @param weekly_pattern_n The number of weekly harmonics.
#' @param alpha The log of the baseline count.
#' @param beta The trend on the log scale, per day.
#' @param gamma_1,gamma_2 The cosine and sine coefficients of the seasonal term.
#' @param gamma_3,gamma_4 The cosine and sine coefficients of the weekly term.
#' @param phi The dispersion. 1 gives a Poisson count, and above 1 a negative
#'   binomial with variance `phi * mu`. Below 1 gives `NA` counts and a warning.
#' @param shift_1 A shift in days, added to `t`, that moves the peaks.
#' @return A `csfmt_rts_data_v1` with one row per day. Its columns include
#'   `date`, `time` (`t`), `wday` (1 is Sunday), `mu`, the mean, and `n`, the
#'   count.
#' @references
#' Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
#' An improved algorithm for outbreak detection in multiple surveillance
#' systems. Statistics in Medicine. 2013.
#' @family data simulation functions
#' @seealso `vignette("csalert", package = "csalert")`, which simulates a series
#'   with a known outbreak.
#' @export
#' @examples
#' library(data.table)
#' set.seed(4)
#' baseline <- simulate_baseline_data(
#'   start_date = as.Date("2018-01-01"),
#'   end_date = as.Date("2019-12-31"),
#'   seasonal_pattern_n = 1,
#'   weekly_pattern_n = 1,
#'   alpha = 3,
#'   beta = 0,
#'   gamma_1 = 0.8,
#'   gamma_2 = 0.6,
#'   gamma_3 = 0.8,
#'   gamma_4 = 0.4,
#'   phi = 4,
#'   shift_1 = 29
#' )
#' print(baseline[, .(date, wday, mu, n)])

simulate_baseline_data <- function(
  start_date,
  end_date,
  seasonal_pattern_n,
  weekly_pattern_n,
  alpha,
  beta,
  gamma_1,
  gamma_2,
  gamma_3,
  gamma_4,
  phi,
  shift_1
) {
  time <- NULL
  trend <- NULL
  seasonal_pattern <- NULL
  weekly_pattern <- NULL
  n <- NULL

  # d <- csalert::gen_csfmt_rts_baseline_data(start_date, end_date)

  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)

  d <- cstidy::csfmt_rts_data_v1(data.table(
    location_code = "norge",
    date = seq.Date(start_date, end_date, by = "day"),
    age = "total",
    sex = "total",
    border = 2020,
    granularity_time = "day"
  ))

  d[, time := seq_len(.N)]
  d[, wday := lubridate::wday(date)]
  t <- seq_len(nrow(d))
  d[, phi := phi]

  if (seasonal_pattern_n == 0 && weekly_pattern_n == 0) {
    d[, mu := exp(alpha + (beta * time))]
  } else {
    if (seasonal_pattern_n == 0) {
      wp_n <- weekly_pattern_n

      d[, trend := alpha + (beta * (time + shift_1))]
      d[, seasonal_pattern := NA]
      d[,
        weekly_pattern := periodic_pattern(
          wp_n,
          gamma_3,
          gamma_4,
          shift_1,
          7,
          time
        )
      ]

      d[, mu := exp(trend + weekly_pattern)]
    } else {
      wp_n <- weekly_pattern_n
      sp_n <- seasonal_pattern_n

      d[, trend := alpha + (beta * (time + shift_1))]
      d[,
        seasonal_pattern := periodic_pattern(
          sp_n,
          gamma_1,
          gamma_2,
          shift_1,
          52 * 7,
          t
        )
      ]
      d[,
        weekly_pattern := periodic_pattern(
          wp_n,
          gamma_3,
          gamma_4,
          shift_1,
          7,
          t
        )
      ]

      d[, mu := exp(trend + seasonal_pattern + weekly_pattern)]
    }
  }

  mu <- d$mu

  if (phi == 1) {
    d[, n := stats::rpois(.N, lambda = mu)]
  } else {
    prob <- 1 / phi
    size <- mu / (phi - 1)
    d[, n := stats::rnbinom(.N, size = size, prob = prob)]
  }

  return(d)
}


#' Add seasonal outbreaks to simulated daily counts
#'
#' @description
#' Adds outbreaks inside a season window to the output of
#' [simulate_baseline_data()], after Noufaily et al. (2019). It adds
#' `n_season_outbreak` outbreaks in each of a random number of years.
#'
#' @details
#' The candidate years are those in `calyear`, except the last, and the function
#' prints the years it picks. The window runs from ISO week `week_season_start` of
#' a year to `week_season_end` of the next. An outbreak starts on a day of the
#' window drawn with random weights.
#'
#' An outbreak adds a Poisson number of cases with mean `10 * m * sd`, where
#' `sd = sqrt(mu * phi)` on the start day. The draw repeats until it is 2 or more,
#' and it calls `set.seed()`, which resets the random stream. The cases spread
#' over the next days by a lognormal delay. Each day is then weighted: 0.5 on
#' Sunday, 2 on Friday and Saturday, and 1 on other days.
#'
#' **It needs `calyear`.** Where `calyear` is `NA`, as from
#' [simulate_baseline_data()] with cstidy 2026.8.21, it adds no outbreak.
#' @param data The output of [simulate_baseline_data()].
#' @param week_season_start The ISO week that starts the season window.
#' @param week_season_peak Not used: the start day is drawn with random
#'   weights, not near the peak.
#' @param week_season_end The ISO week, in the next year, that ends the window.
#' @param n_season_outbreak The number of outbreaks in each outbreak year.
#' @param m The size factor of an outbreak.
#' @return A copy of `data` with the cases added to `n`, and these columns:
#' * `sd` and `weight`,
#' * `seasonal_outbreak`: 1 on an outbreak day,
#' * `seasonal_outbreak_n`: the cases,
#' * `seasonal_outbreak_n_rw`: the weighted cases, which are added to `n`.
#' @references
#' Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
#' An improved algorithm for outbreak detection in multiple surveillance
#' systems. Statistics in Medicine. 2013.
#' @family data simulation functions
#' @seealso `vignette("csalert", package = "csalert")`, which simulates a series
#'   with a known outbreak.
#' @export
#' @examples
#' library(data.table)
#' set.seed(4)
#' baseline <- simulate_baseline_data(
#'   start_date = as.Date("2018-01-01"),
#'   end_date = as.Date("2019-12-31"),
#'   seasonal_pattern_n = 1,
#'   weekly_pattern_n = 1,
#'   alpha = 3,
#'   beta = 0,
#'   gamma_1 = 0.8,
#'   gamma_2 = 0.6,
#'   gamma_3 = 0.8,
#'   gamma_4 = 0.4,
#'   phi = 4,
#'   shift_1 = 29
#' )
#' d <- simulate_seasonal_outbreak_data(
#'   baseline,
#'   week_season_start = 40,
#'   week_season_peak = 4,
#'   week_season_end = 20,
#'   n_season_outbreak = 1
#' )
#' print(d[, .(date, n, seasonal_outbreak, seasonal_outbreak_n)])

simulate_seasonal_outbreak_data <- function(
  data,
  week_season_start = 40,
  week_season_peak = 4,
  week_season_end = 20,
  n_season_outbreak = 1,
  m = 50
) {
  mu <- NULL
  phi <- NULL
  weight <- NULL
  seasonal_outbreak <- NULL
  seasonal_outbreak_n <- NULL
  seasonal_outbreak_rw <- NULL
  isoyearweek <- NULL
  years_out <- NULL
  seasonal_outbreak_n_rw <- NULL
  n <- NULL

  d <- copy(data)
  N <- nrow(d)

  d[, sd := sqrt(mu * phi)]

  ## wdays reweight ## should this be part of parameters?
  d[wday == 1, weight := 0.5]
  d[wday == 2, weight := 1]
  d[wday == 3, weight := 1]
  d[wday == 4, weight := 1]
  d[wday == 5, weight := 1]
  d[wday == 6, weight := 2]
  d[wday == 7, weight := 2]

  ## select year were there is seasonal outbreak

  n_year <- length(unique(d$calyear))
  years <- sort(unique(d$calyear))[1:(n_year - 1)]

  # random sampling of numbers of years with seasonal outbreak
  n_out <- sample(seq_along(years), 1)
  years_out <- sort(sample(years, n_out, replace = FALSE))

  print(years_out)

  d[, seasonal_outbreak := 0]
  d[, seasonal_outbreak_n := 0]
  d[, seasonal_outbreak_n_rw := 0]

  for (y in years_out) {
    # set.seed(y)

    wtime <- c(
      paste(y, c(week_season_start:52), sep = "-"),
      paste(
        y + 1,
        stringr::str_pad(c(1:week_season_end), 2, pad = "0"),
        sep = "-"
      )
    )
    time <- d[isoyearweek %in% wtime]$time

    # probability of outbreak start around the peak of seasoanl
    start_seasonal_outbreak <- sample(
      time,
      n_season_outbreak,
      replace = FALSE,
      prob = abs(stats::rnorm(length(time)))
    )

    # number of cases for outbreat
    n_cases_outbreak <- rep(0, n_season_outbreak)

    size_outbreak <- 1
    sou <- 1

    for (i in 1:n_season_outbreak) {
      while (size_outbreak < 2) {
        set.seed(sou)
        sd <- d[time == start_seasonal_outbreak[i]]$sd
        size_outbreak <- stats::rpois(1, sd * m * 10)
        sou <- sou + 1
      }

      n_cases_outbreak[i] <- size_outbreak

      # Cases are distributed from the start of outbreak using a log normal distribution

      outbreak <- stats::rlnorm(n_cases_outbreak[i], meanlog = 0, sdlog = 0.5)

      h <- graphics::hist(
        outbreak,
        breaks = seq(0, ceiling(max(outbreak)), 0.1),
        plot = FALSE
      )

      outbreak_n <- h$counts
      duration <- start_seasonal_outbreak[i]:(start_seasonal_outbreak[i] +
        length(outbreak_n) -
        1)

      d[time %in% duration, seasonal_outbreak_n := outbreak_n]
      d[time %in% duration, seasonal_outbreak_n_rw := outbreak_n * weight]
      d[time %in% duration, seasonal_outbreak := 1]
    }
  }

  d[, n := n + seasonal_outbreak_n_rw]
  return(d)
}


#' Add short outbreaks to the end of simulated daily counts
#'
#' @description
#' Adds `n_sp_outbreak` short outbreaks to the output of
#' [simulate_baseline_data()], after Noufaily et al. (2019). Each starts on a
#' random day in the last 344 days, 49 weeks, of the data.
#'
#' @details
#' The size and the spread are as in [simulate_seasonal_outbreak_data()], over
#' about half as many days, and with no day-of-week weight on `n`. The size draw
#' also calls `set.seed()`.
#' @param data The output of [simulate_baseline_data()].
#' @param n_sp_outbreak The number of outbreaks.
#' @param m The size factor of an outbreak: the mean size is `10 * m * sd`.
#' @return A copy of `data` with the cases added to `n`, and these columns:
#' * `sd` and `weight`,
#' * `sp_outbreak`: 2 on an outbreak day and 0 on other days,
#' * `sp_outbreak_n`: the cases, which are added to `n`,
#' * `sp_outbreak_n_rw`: the weighted cases, which `n` does not use.
#' @references
#' Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
#' An improved algorithm for outbreak detection in multiple surveillance
#' systems. Statistics in Medicine. 2013.
#' @family data simulation functions
#' @seealso `vignette("csalert", package = "csalert")`, which runs it.
#' @export
#' @examples
#' library(data.table)
#' set.seed(4)
#' baseline <- simulate_baseline_data(
#'   start_date = as.Date("2018-01-01"),
#'   end_date = as.Date("2019-12-31"),
#'   seasonal_pattern_n = 1,
#'   weekly_pattern_n = 1,
#'   alpha = 3,
#'   beta = 0,
#'   gamma_1 = 0.8,
#'   gamma_2 = 0.6,
#'   gamma_3 = 0.8,
#'   gamma_4 = 0.4,
#'   phi = 4,
#'   shift_1 = 29
#' )
#' d <- simulate_spike_outbreak_data(
#'   baseline,
#'   n_sp_outbreak = 1,
#'   m = 2
#' )
#' print(d[, .(date, n, sp_outbreak, sp_outbreak_n)])

simulate_spike_outbreak_data <- function(data, n_sp_outbreak = 1, m) {
  mu <- NULL
  phi <- NULL
  weight <- NULL
  sp_outbreak_n <- NULL
  sp_outbreak_n_rw <- NULL
  n <- NULL
  sp_outbreak <- NULL
  n <- NULL

  d <- copy(data)

  N <- nrow(d)
  d[, sd := sqrt(mu * phi)]

  d[wday == 1, weight := 0.5]
  d[wday == 2, weight := 1]
  d[wday == 3, weight := 1]
  d[wday == 4, weight := 1]
  d[wday == 5, weight := 1]
  d[wday == 6, weight := 2]
  d[wday == 7, weight := 2]

  wtime <- (nrow(d) - 49 * 7):nrow(d)

  time <- d[time %in% wtime]$time

  startoutbk <- sample(time, n_sp_outbreak, replace = FALSE)

  # OUTBREAK SIZE OF CASES

  n_cases_outbreak <- rep(0, n_sp_outbreak)
  soutbk <- 1
  sou <- 1

  d[, sp_outbreak_n := 0]
  d[, sp_outbreak_n_rw := 0]

  for (i in 1:n_sp_outbreak) {
    while (soutbk < 2) {
      set.seed(sou)
      sd <- d[time == startoutbk[i]]$sd
      soutbk <- stats::rpois(1, sd * m * 10)
      sou <- sou + 1
    }

    n_cases_outbreak[i] <- soutbk

    # Cases are distributed from the start of outbreak using a log normal distribution
    outbreak <- stats::rlnorm(n_cases_outbreak[i], meanlog = 0, sdlog = 0.5)
    h <- graphics::hist(
      outbreak,
      breaks = seq(0, ceiling(max(outbreak)), 0.2),
      plot = FALSE
    )
    outbreak_n <- h$counts
    duration <- startoutbk[i]:(startoutbk[i] + length(outbreak_n) - 1)

    d[time %in% duration, sp_outbreak_n := outbreak_n]
    d[time %in% duration, sp_outbreak_n_rw := outbreak_n * weight]
    d[time %in% duration, sp_outbreak := 2]
  }

  d[is.na(sp_outbreak), sp_outbreak := 0]
  d[is.na(sp_outbreak_n), sp_outbreak_n := 0]
  d[is.na(sp_outbreak_n_rw), sp_outbreak_n_rw := 0]

  d[, n := n + sp_outbreak_n]

  return(d)
}


#' Multiply simulated counts on public holidays
#'
#' @description
#' Multiplies the count `n` by `holiday_effect` on each date that `holiday_data`
#' marks as a holiday.
#'
#' @details
#' An integer `n`, as from [simulate_baseline_data()], stays an integer. So a
#' factor that gives a fraction truncates the count, with a warning.
#' @param data A `csfmt_rts_data_v1` with `date` and `n`.
#' @param holiday_data A data.table with `date` and a logical `is_holiday`.
#' @param holiday_effect The factor for a holiday.
#' @return A copy of `data` with `n` changed, and a `holiday` column: the value of
#'   `is_holiday` on the dates in `holiday_data`, and `NA` on other dates.
#' @family data simulation functions
#' @seealso `vignette("csalert", package = "csalert")`, which runs it.
#' @export
#' @examples
#' library(data.table)
#' set.seed(4)
#' baseline <- simulate_baseline_data(
#'   start_date = as.Date("2018-01-01"),
#'   end_date = as.Date("2019-12-31"),
#'   seasonal_pattern_n = 1,
#'   weekly_pattern_n = 1,
#'   alpha = 3,
#'   beta = 0,
#'   gamma_1 = 0.8,
#'   gamma_2 = 0.6,
#'   gamma_3 = 0.8,
#'   gamma_4 = 0.4,
#'   phi = 4,
#'   shift_1 = 29
#' )
#' holidays <- data.table(
#'   date = as.Date(c("2018-12-25", "2019-01-01", "2019-12-25")),
#'   is_holiday = TRUE
#' )
#' d <- add_holiday_effect(baseline, holiday_data = holidays, holiday_effect = 2)
#' print(d[holiday == TRUE, .(date, n, holiday)])

add_holiday_effect <- function(data, holiday_data, holiday_effect = 2) {
  holiday <- NULL
  is_holiday <- NULL
  n <- NULL
  d <- NULL

  d <- copy(data)

  d[
    holiday_data,
    on = c("date"),
    holiday := is_holiday
  ]

  d[holiday == TRUE, n := n * holiday_effect]

  return(d)
}

# run_simulation <- function(start_date,
#                            end_date,
#                            seasonal_pattern_n,
#                            weekly_pattern_n,
#                            week_season_start,
#                            week_season_peak ,
#                            week_season_end,
#                            n_season_outbreak,
#                            num_sp_outbreak,
#                            baseline_param_list = list(alpha, beta, gamma1,gamma3,gamma4,phi,shift),
#                            outbreak_param_list = list(m),
#                            nsim) {
#
#
#     retval <- list()
#
#     for (i in 1:(nsim)) {
#
#           data <- simulate_baseline_data(start_date,
#                                      end_date,
#                                      seasonal_pattern_n,
#                                      weekly_pattern_n,
#                                      baseline_param_list)
#       if (seasonal_pattern_n!=0) {
#
#           data <- simulate_seasonal_outbreak_data(data,
#                                               week_season_start,
#                                               week_season_peak ,
#                                               week_season_end,
#                                               n_season_outbreak,
#                                               baseline_param_list,
#                                               outbreak_param_list)
#       }
#
#       data <- simulate_spike_outbreak_data(data,
#                                            num_sp_outbreak,
#                                            baseline_param_list,
#                                            outbreak_param_list)
#
#       retval[[i]] <-  data
#
#
#     }
#
#     return(retval)
#
# }

# sim <- run_simulation(nsim=100,
#                start_date = as.Date("2012-01-01"),
#                end_date = as.Date("2019-12-31"),
#                seasonal_pattern_n = 1,
#                weekly_pattern_n = 1,
#                week_season_start = 40,
#                week_season_peak = 4,
#                week_season_end = 20,
#                n_season_outbreak = 1,
#                num_sp_outbreak = 1,
#                baseline_param_list = list(alpha = 3, beta = 0,gamma1 = 0.8, gamma2 = 0.6, gamma3 = 0.8, gamma4 = 0.4, phi = 4,shift = 29 ),
#                outbreak_param_list = list(m=2)
# )
