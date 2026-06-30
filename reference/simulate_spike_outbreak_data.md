# Add spiked outbreaks to simulated data

Adds spiked outbreaks to a simulated baseline time series, following
Noufaily et al. (2019). The method is similar to
[`simulate_seasonal_outbreak_data`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md),
but the outbreaks are shorter in duration and are added only within the
last year of data (the prediction period). A spiked outbreak can start
at any week during that period.

## Usage

``` r
simulate_spike_outbreak_data(data, n_sp_outbreak = 1, m)
```

## Arguments

- data:

  A `csfmt_rts_data_v1` data object, typically the output of
  [`simulate_baseline_data`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md).

- n_sp_outbreak:

  Number of spiked outbreaks to be simulated.

- m:

  Parameter to determine the size of the outbreak (m times the standard
  deviation of the baseline count at the starting day of the spiked
  outbreak).

## Value

A `csfmt_rts_data_v1` (`data.table`) equal to `data` with the simulated
spiked outbreak counts added to column `n` and additional columns
describing the outbreaks (e.g. `sp_outbreak`, `sp_outbreak_n`).

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
