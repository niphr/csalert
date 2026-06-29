# Simulate seasonal outbreaks —-

Simulation of seasonal outbreaks for syndromes/diseases that follows
seasonal trends. Seasonal outbreaks are more variable both in size and
timing than seasonal patterns. The number of seasonal outbreaks occur in
a year are defined by n_season_outbreak. The parameters
week_season_start and week_season_end define the season window. The
start of the seasonal outbreak is drawn from the season window weeks,
with higher probability of outbreak occurs around the peak of the season
(week_season_peak). The seasonal outbreak size (excess number of cases
that occurs during the outbreak) is simulated using a poisson
distribution as described in Noufaily et al. (2019).

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

  A csfmt_rds data object

- week_season_start:

  Starting season week number

- week_season_peak:

  Peak of the season week number

- week_season_end:

  Ending season week number

- n_season_outbreak:

  Number of seasonal outbreaks to be simulated

- m:

  Parameter to determine the size of the outbreak (m times the standard
  deviation of the baseline count at the starting day of the seasonal
  outbreak)

## Value

A csfmt_rts_data_v1, data.table
