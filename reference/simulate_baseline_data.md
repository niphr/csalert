# Simulate daily counts with no outbreak

Simulates daily counts from a Poisson or negative binomial model with a
trend, a seasonal pattern and a day-of-week pattern, after Noufaily et
al. (2019). Use it to make a series with a known truth.

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

- start_date, end_date:

  The first and last day, as a `Date` or a `"YYYY-MM-DD"` string.

- seasonal_pattern_n:

  The number of seasonal harmonics: 0 for none, 1 for an annual pattern,
  2 to add a half-year harmonic.

- weekly_pattern_n:

  The number of weekly harmonics.

- alpha:

  The log of the baseline count.

- beta:

  The trend on the log scale, per day.

- gamma_1, gamma_2:

  The cosine and sine coefficients of the seasonal term.

- gamma_3, gamma_4:

  The cosine and sine coefficients of the weekly term.

- phi:

  The dispersion. 1 gives a Poisson count, and above 1 a negative
  binomial with variance `phi * mu`. Below 1 gives `NA` counts and a
  warning.

- shift_1:

  A shift in days, added to `t`, that moves the peaks.

## Value

A `csfmt_rts_data_v1` with one row per day. Its columns include `date`,
`time` (`t`), `wday` (1 is Sunday), `mu`, the mean, and `n`, the count.

## Details

On day `t`, from 1, the log of the mean is
`alpha + beta * (t + shift_1)` plus a seasonal term and a weekly term.
With `u = 2 * pi * (t + shift_1) / p`, each term sums
`a * cos(l * u) + b * sin(l * u)` over `l = 1, ..., n`:

- seasonal: `p = 364`, `n = seasonal_pattern_n`, `a = gamma_1`,
  `b = gamma_2`,

- weekly: `p = 7`, `n = weekly_pattern_n`, `a = gamma_3`, `b = gamma_4`.

With both `n` at 0, the log of the mean is `alpha + beta * t`. With
`seasonal_pattern_n > 0`, `weekly_pattern_n = 0` still adds a weekly
term, because `1:0` in R is `c(1, 0)`.

## References

Noufaily A, Enki DG, Farrington P, Garthwaite P, Andrews N, Charlett A.
An improved algorithm for outbreak detection in multiple surveillance
systems. Statistics in Medicine. 2013.

## See also

[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md),
which simulates a series with a known outbreak.

Other data simulation functions:
[`add_holiday_effect()`](https://niphr.github.io/csalert/reference/add_holiday_effect.md),
[`simulate_seasonal_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md),
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
