# Determine the short term trend of a surveillance time series

Fits a quasi-Poisson regression over a moving window of recent
observations of a `surveillance` `sts` object and sets the alarm slot to
1 for time points with a significant increasing trend (0 otherwise). The
method is based upon a published analytics strategy by Benedetti (2019)
\<doi:10.5588/pha.19.0002\>. This function was frozen on 2024-06-24 and
operates on `sts` objects.

## Usage

``` r
short_term_trend_sts_v1(sts, control = list(w = 5, alpha = 0.05))
```

## Arguments

- sts:

  Data object of type sts.

- control:

  Control object, a named list with several elements.

  w

  :   Length of the window that is being analyzed.

  alpha

  :   Significance level for change in trend.

## Value

sts object with the alarms slot set to 0/1 if not-increasing/increasing.

## Examples

``` r
d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
d <- d[granularity_time=="isoyearweek"]
sts <- surveillance::sts(
  observed = d$hospitalization_with_covid19_as_primary_cause_n, # weekly number of cases
  start = c(d$isoyear[1], d$isoweek[1]), # first week of the time series
  frequency = 52
)
x <- csalert::short_term_trend_sts_v1(
  sts,
  control = list(
    w = 5,
    alpha = 0.05
  )
)
plot(x)
```
