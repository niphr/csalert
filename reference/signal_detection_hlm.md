# Determine the short term trend of a timeseries

The method is based upon a published analytics strategy by Benedetti
(2019) \<doi:10.5588/pha.19.0002\>.

## Usage

``` r
signal_detection_hlm(x, ...)

# S3 method for class 'csfmt_rts_data_v1'
signal_detection_hlm(
  x,
  value,
  baseline_isoyears = 5,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = 2,
  value_naming_prefix = "from_numerator",
  remove_training_data = FALSE,
  ...
)
```

## Arguments

- x:

  Data object

- ...:

  Not in use.

- value:

  Character of name of value

- baseline_isoyears:

  Number of years in the past you want to include as baseline

- remove_last_isoyearweeks:

  Number of isoyearweeks you want to remove at the end (due to
  unreliable data)

- forecast_isoyearweeks:

  Number of isoyearweeks you want to forecast into the future

- value_naming_prefix:

  "from_numerator", "generic", or a custom prefix

- remove_training_data:

  Boolean. If TRUE, removes the training data (i.e.
  1:(trend_isoyearweeks-1)) from the returned dataset.

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
res <- csalert::signal_detection_hlm(
  d,
  value = "hospitalization_with_covid19_as_primary_cause_n",
  baseline_isoyears = 1
)
print(res[, .(
  isoyearweek,
  hospitalization_with_covid19_as_primary_cause_n,
  hospitalization_with_covid19_as_primary_cause_forecasted_n,
  hospitalization_with_covid19_as_primary_cause_forecasted_n_forecast,
  hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q50x0_n,
  hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q99x5_n,
  hospitalization_with_covid19_as_primary_cause_n_status
)])
#>      isoyearweek hospitalization_with_covid19_as_primary_cause_n
#>           <char>                                           <int>
#>   1:     2020-08                                               0
#>   2:     2020-09                                               0
#>   3:     2020-10                                               2
#>   4:     2020-11                                              50
#>   5:     2020-12                                             188
#>  ---                                                            
#> 114:     2022-16                                             137
#> 115:     2022-17                                              74
#> 116:     2022-18                                              10
#> 117:     2022-19                                              NA
#> 118:     2022-20                                              NA
#>      hospitalization_with_covid19_as_primary_cause_forecasted_n
#>                                                           <int>
#>   1:                                                          0
#>   2:                                                          0
#>   3:                                                          2
#>   4:                                                         50
#>   5:                                                        188
#>  ---                                                           
#> 114:                                                        137
#> 115:                                                         74
#> 116:                                                         10
#> 117:                                                         66
#> 118:                                                         59
#>      hospitalization_with_covid19_as_primary_cause_forecasted_n_forecast
#>                                                                   <lgcl>
#>   1:                                                               FALSE
#>   2:                                                               FALSE
#>   3:                                                               FALSE
#>   4:                                                               FALSE
#>   5:                                                               FALSE
#>  ---                                                                    
#> 114:                                                               FALSE
#> 115:                                                               FALSE
#> 116:                                                               FALSE
#> 117:                                                                TRUE
#> 118:                                                                TRUE
#>      hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q50x0_n
#>                                                                            <num>
#>   1:                                                                          NA
#>   2:                                                                          NA
#>   3:                                                                          NA
#>   4:                                                                          NA
#>   5:                                                                          NA
#>  ---                                                                            
#> 114:                                                                         125
#> 115:                                                                          92
#> 116:                                                                          69
#> 117:                                                                          66
#> 118:                                                                          59
#>      hospitalization_with_covid19_as_primary_cause_baseline_predinterval_q99x5_n
#>                                                                            <num>
#>   1:                                                                          NA
#>   2:                                                                          NA
#>   3:                                                                          NA
#>   4:                                                                          NA
#>   5:                                                                          NA
#>  ---                                                                            
#> 114:                                                                         255
#> 115:                                                                         184
#> 116:                                                                          77
#> 117:                                                                          79
#> 118:                                                                          79
#>      hospitalization_with_covid19_as_primary_cause_n_status
#>                                                      <fctr>
#>   1:                                               training
#>   2:                                               training
#>   3:                                               training
#>   4:                                               training
#>   5:                                               training
#>  ---                                                       
#> 114:                                                   null
#> 115:                                                   null
#> 116:                                                   null
#> 117:                                               forecast
#> 118:                                               forecast
```
