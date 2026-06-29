# Determine the short term trend of a timeseries

The method is based upon a published analytics strategy by Benedetti
(2019) \<doi:10.5588/pha.19.0002\>.

## Usage

``` r
short_term_trend(x, ...)

# S3 method for class 'csfmt_rts_data_v1'
short_term_trend(
  x,
  numerator,
  denominator = NULL,
  prX = 100,
  trend_isoyearweeks = 6,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = trend_isoyearweeks,
  numerator_naming_prefix = "from_numerator",
  denominator_naming_prefix = "from_denominator",
  statistics_naming_prefix = "universal",
  remove_training_data = FALSE,
  include_decreasing = FALSE,
  alpha = 0.05,
  ...
)
```

## Arguments

- x:

  Data object

- ...:

  Not in use.

- numerator:

  Character of name of numerator

- denominator:

  Character of name of denominator (optional)

- prX:

  If using denominator, what scaling factor should be used for
  numerator/denominator?

- trend_isoyearweeks:

  Same as trend_dates, but used if granularity_geo=='isoyearweek'

- remove_last_isoyearweeks:

  Same as remove_last_dates, but used if granularity_geo=='isoyearweek'

- forecast_isoyearweeks:

  Same as forecast_dates, but used if granularity_geo=='isoyearweek'

- numerator_naming_prefix:

  "from_numerator", "generic", or a custom prefix

- denominator_naming_prefix:

  "from_denominator", "generic", or a custom prefix

- statistics_naming_prefix:

  "universal" (one variable for trend status, one variable for doubling
  dates), "from_numerator_and_prX" (If denominator is NULL, then one
  variable corresponding to numerator. If denominator exists, then one
  variable for each of the prXs)

- remove_training_data:

  Boolean. If TRUE, removes the training data (i.e. 1:(trend_dates-1) or
  1:(trend_isoyearweeks-1)) from the returned dataset.

- include_decreasing:

  If true, then \*\_trend\*\_status contains the levels c("training",
  "forecast", "decreasing", "null", "increasing"), otherwise the levels
  c("training", "forecast", "notincreasing", "increasing").

- alpha:

  Significance level for change in trend.

## Value

The original csfmt_rts_data_v1 dataset with extra columns.
\*\_trend\*\_status contains a factor with levels c("training",
"forecast", "decreasing", "null", "increasing"), while
\*\_doublingdays\* contains the expected number of days before the
numerator doubles.

## Examples

``` r
d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
d <- d[granularity_time=="isoyearweek"]
res <- csalert::short_term_trend(
  d,
  numerator = "hospitalization_with_covid19_as_primary_cause_n",
  trend_isoyearweeks = 6
)
print(res[, .(
  isoyearweek,
  hospitalization_with_covid19_as_primary_cause_n,
  hospitalization_with_covid19_as_primary_cause_trend0_41_status
)])
#>      isoyearweek hospitalization_with_covid19_as_primary_cause_n
#>           <char>                                           <int>
#>   1:     2020-08                                               0
#>   2:     2020-09                                               0
#>   3:     2020-10                                               2
#>   4:     2020-11                                              50
#>   5:     2020-12                                             188
#>  ---                                                            
#> 118:     2022-20                                              NA
#> 119:     2022-21                                              NA
#> 120:     2022-22                                              NA
#> 121:     2022-23                                              NA
#> 122:     2022-24                                              NA
#>      hospitalization_with_covid19_as_primary_cause_trend0_41_status
#>                                                              <fctr>
#>   1:                                                       training
#>   2:                                                       training
#>   3:                                                       training
#>   4:                                                       training
#>   5:                                                       training
#>  ---                                                               
#> 118:                                                       forecast
#> 119:                                                       forecast
#> 120:                                                       forecast
#> 121:                                                       forecast
#> 122:                                                       forecast
```
