# Add seasonal outbreaks to simulated daily counts

Adds outbreaks inside a season window to the output of
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
after Noufaily et al. (2019). It adds `n_season_outbreak` outbreaks in
each of a random number of years.

## Usage

``` r
simulate_seasonal_outbreak_data(
  data,
  week_season_start = 40,
  week_season_peak = 4,
  week_season_end = 20,
  n_season_outbreak = 1,
  m = 50
)
```

## Arguments

- data:

  The output of
  [`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md).

- week_season_start:

  The ISO week that starts the season window.

- week_season_peak:

  Not used: the start day is drawn with random weights, not near the
  peak.

- week_season_end:

  The ISO week, in the next year, that ends the window.

- n_season_outbreak:

  The number of outbreaks in each outbreak year.

- m:

  The size factor of an outbreak.

## Value

A copy of `data` with the cases added to `n`, and these columns:

- `sd` and `weight`,

- `seasonal_outbreak`: 1 on an outbreak day,

- `seasonal_outbreak_n`: the cases,

- `seasonal_outbreak_n_rw`: the weighted cases, which are added to `n`.

## Details

The candidate years are those in `calyear`, except the last, and the
function prints the years it picks. The window runs from ISO week
`week_season_start` of a year to `week_season_end` of the next. An
outbreak starts on a day of the window drawn with random weights.

An outbreak adds a Poisson number of cases with mean `10 * m * sd`,
where `sd = sqrt(mu * phi)` on the start day. The draw repeats until it
is 2 or more, and it calls
[`set.seed()`](https://rdrr.io/r/base/Random.html), which resets the
random stream. The cases spread over the next days by a lognormal delay.
Each day is then weighted: 0.5 on Sunday, 2 on Friday and Saturday, and
1 on other days.

**It needs `calyear`.** Where `calyear` is `NA`, as from
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md)
with cstidy 2026.8.21, it adds no outbreak.

## References

Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
An improved algorithm for outbreak detection in multiple surveillance
systems. Statistics in Medicine. 2013.

## See also

[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md),
which simulates a series with a known outbreak.

Other data simulation functions:
[`add_holiday_effect()`](https://niphr.github.io/csalert/reference/add_holiday_effect.md),
[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md),
[`simulate_spike_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_spike_outbreak_data.md)

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
d <- simulate_seasonal_outbreak_data(
  baseline,
  week_season_start = 40,
  week_season_peak = 4,
  week_season_end = 20,
  n_season_outbreak = 1
)
#> integer(0)
print(d[, .(date, n, seasonal_outbreak, seasonal_outbreak_n)])
#>            date     n seasonal_outbreak seasonal_outbreak_n
#>          <Date> <num>             <num>               <num>
#>   1: 2018-01-01    64                 0                   0
#>   2: 2018-01-02    32                 0                   0
#>   3: 2018-01-03    19                 0                   0
#>   4: 2018-01-04    37                 0                   0
#>   5: 2018-01-05    72                 0                   0
#>  ---                                                       
#> 726: 2019-12-27    68                 0                   0
#> 727: 2019-12-28   109                 0                   0
#> 728: 2019-12-29   139                 0                   0
#> 729: 2019-12-30    60                 0                   0
#> 730: 2019-12-31    41                 0                   0
```
