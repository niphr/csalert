# Simulate baseline data —- Simulation of baseline data.

This function simulates a time series of daily counts in the absence of
outbreaks. Data is simulated using a poisson/negative binomial model as
described in Noufaily et al. (2019). Properties of time series such as
frequency of baseline observations, trend, seasonal and weekly pattern
can be specified in the simulation.

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

A csfmt_rts_data_v1, data.table containing a time series of counts

- wday:

  day-of-the week

- n:

  cases

## Examples

``` r
baseline  <- simulate_baseline_data(
start_date = as.Date("2012-01-01"),
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
shift_1 = 29 )
```
