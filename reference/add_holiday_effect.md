# Apply a public holiday effect to simulated data

Multiplies the daily counts on public holidays by a fixed factor, so
that simulated data can reflect the effect of holidays on a time series
of daily counts.

## Usage

``` r
add_holiday_effect(data, holiday_data, holiday_effect = 2)
```

## Arguments

- data:

  A `csfmt_rts_data_v1` data object, typically the output of
  [`simulate_baseline_data`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md).

- holiday_data:

  A `data.table` with a `date` column and a logical `is_holiday` column,
  used to flag which dates are public holidays.

- holiday_effect:

  Multiplicative factor applied to the count `n` on holidays.

## Value

A `csfmt_rts_data_v1` (`data.table`) equal to `data` with the count `n`
multiplied by `holiday_effect` on flagged holidays, and a `holiday`
column indicating those dates.

## Examples

``` r
library(data.table)
#> 
#> Attaching package: ‘data.table’
#> The following object is masked from ‘package:base’:
#> 
#>     %notin%
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
holidays <- data.table(
  date = as.Date(c("2018-12-25", "2019-01-01", "2019-12-25")),
  is_holiday = TRUE
)
d <- add_holiday_effect(baseline, holiday_data = holidays, holiday_effect = 2)
print(d[holiday == TRUE, .(date, n, holiday)])
#>          date     n holiday
#>        <Date> <int>  <lgcl>
#> 1: 2018-12-25    62    TRUE
#> 2: 2019-01-01    44    TRUE
#> 3: 2019-12-25    26    TRUE
```
