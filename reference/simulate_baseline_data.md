# Simulate baseline surveillance data

Simulates a time series of daily counts in the absence of outbreaks. The
counts are drawn from a Poisson or negative binomial model following the
approach of Noufaily et al. (2019). The baseline frequency, linear
trend, seasonal pattern and day-of-the-week pattern are all controlled
through the function arguments.

## Usage

``` r
simulate_baseline_data(
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
)
```

## Arguments

- start_date:

  Starting date of the simulation period. Date is in the format of
  'yyyy-mm-dd'.

- end_date:

  Ending date of the simulation period. Date is in the format of
  'yyyy-mm-dd'.

- seasonal_pattern_n:

  Number of seasonal patterns. For no seasonal pattern
  seasonal_pattern_n = 0. Seasonal_pattern_n = 1 represents annual
  pattern. Seasonal_pattern_n = 2 indicates biannual pattern.

- weekly_pattern_n:

  Number of weekly patterns. For no specific weekly pattern,
  weekly_pattern_n = 0. Weekly_pattern_n = 1 represents one weekly peak.

- alpha:

  The parameter is used to specify the baseline frequencies of reports

- beta:

  The parameter is used to specify to specify linear trend

- gamma_1:

  The parameter is used to specify the seasonal pattern

- gamma_2:

  The parameter is used to specify the seasonal pattern

- gamma_3:

  The parameter is used to specify day-of-the week pattern

- gamma_4:

  The parameter is used to specify day-of-the week pattern

- phi:

  Dispersion parameter. If phi =0, a Poisson model is used to simulate
  baseline data.

- shift_1:

  Horizontal shift parameter to help control over week/month peaks.

## Value

A `csfmt_rts_data_v1` (`data.table`) holding one row per day over the
simulation period, including the columns:

- date:

  Calendar date of the observation.

- wday:

  Day of the week.

- mu:

  Expected count from the baseline model.

- n:

  Simulated count.

## References

Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
An improved algorithm for outbreak detection in multiple surveillance
systems. Statistics in Medicine. 2013.

## Examples

``` r
library(data.table)
set.seed(4)
baseline <- simulate_baseline_data(
  start_date = as.Date("2018-01-01"),
  end_date = as.Date("2019-12-31"),
  seasonal_pattern_n = 1,
  weekly_pattern_n = 1,
  alpha = 3,
  beta = 0,
  gamma_1 = 0.8,
  gamma_2 = 0.6,
  gamma_3 = 0.8,
  gamma_4 = 0.4,
  phi = 4,
  shift_1 = 29
)
print(baseline[, .(date, wday, mu, n)])
#>            date  wday        mu     n
#>          <Date> <num>     <num> <int>
#>   1: 2018-01-01     2  66.95830    64
#>   2: 2018-01-02     3  31.40319    32
#>   3: 2018-01-03     4  22.23175    19
#>   4: 2018-01-04     5  30.85457    37
#>   5: 2018-01-05     6  65.65786    72
#>  ---                                 
#> 726: 2019-12-27     6  64.73862    68
#> 727: 2019-12-28     7 119.96484   109
#> 728: 2019-12-29     1 121.67202   139
#> 729: 2019-12-30     2  66.95830    60
#> 730: 2019-12-31     3  31.40319    41
```
