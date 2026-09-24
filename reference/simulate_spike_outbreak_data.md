# Add short outbreaks to the end of simulated daily counts

Adds `n_sp_outbreak` short outbreaks to the output of
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
after Noufaily et al. (2019). Each starts on a random day in the last
344 days, 49 weeks, of the data.

## Usage

``` r
simulate_spike_outbreak_data(data, n_sp_outbreak = 1, m)
```

## Arguments

- data:

  The output of
  [`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md).

- n_sp_outbreak:

  The number of outbreaks.

- m:

  The size factor of an outbreak: the mean size is `10 * m * sd`.

## Value

A copy of `data` with the cases added to `n`, and these columns:

- `sd` and `weight`,

- `sp_outbreak`: 2 on an outbreak day and 0 on other days,

- `sp_outbreak_n`: the cases, which are added to `n`,

- `sp_outbreak_n_rw`: the weighted cases, which `n` does not use.

## Details

The size and the spread are as in
[`simulate_seasonal_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md),
over about half as many days, and with no day-of-week weight on `n`. The
size draw also calls [`set.seed()`](https://rdrr.io/r/base/Random.html).

## References

Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
An improved algorithm for outbreak detection in multiple surveillance
systems. Statistics in Medicine. 2013.

## See also

[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md),
which runs it.

Other data simulation functions:
[`add_holiday_effect()`](https://niphr.github.io/csalert/reference/add_holiday_effect.md),
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
[`simulate_seasonal_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md)

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
d <- simulate_spike_outbreak_data(
  baseline,
  n_sp_outbreak = 1,
  m = 2
)
print(d[, .(date, n, sp_outbreak, sp_outbreak_n)])
#>            date     n sp_outbreak sp_outbreak_n
#>          <Date> <num>       <num>         <num>
#>   1: 2018-01-01    64           0             0
#>   2: 2018-01-02    32           0             0
#>   3: 2018-01-03    19           0             0
#>   4: 2018-01-04    37           0             0
#>   5: 2018-01-05    72           0             0
#>  ---                                           
#> 726: 2019-12-27    68           0             0
#> 727: 2019-12-28   109           0             0
#> 728: 2019-12-29   139           0             0
#> 729: 2019-12-30    60           0             0
#> 730: 2019-12-31    41           0             0
```
