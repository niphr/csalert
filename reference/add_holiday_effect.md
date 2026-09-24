# Multiply simulated counts on public holidays

Multiplies the count `n` by `holiday_effect` on each date that
`holiday_data` marks as a holiday.

## Usage

``` r
add_holiday_effect(data, holiday_data, holiday_effect = 2)
```

## Arguments

- data:

  A `csfmt_rts_data_v1` with `date` and `n`.

- holiday_data:

  A data.table with `date` and a logical `is_holiday`.

- holiday_effect:

  The factor for a holiday.

## Value

A copy of `data` with `n` changed, and a `holiday` column: the value of
`is_holiday` on the dates in `holiday_data`, and `NA` on other dates.

## Details

An integer `n`, as from
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
stays an integer. So a factor that gives a fraction truncates the count,
with a warning.

## See also

[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md),
which runs it.

Other data simulation functions:
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
[`simulate_seasonal_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md),
[`simulate_spike_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_spike_outbreak_data.md)

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
