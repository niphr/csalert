# Flag weeks above a historical limit

Flags a week as `high` above the historical limit, the 99.5% quantile of
a normal fitted to the same weeks in earlier years. The ensemble method
compares every draw with the limit.

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

# S3 method for class 'csfmt_rts_data_v3'
signal_detection_hlm(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
signal_detection_hlm(x, measure, baseline_isoyears = 5, ...)
```

## Arguments

- x:

  A `csfmt_ensemble_v3`, or a deprecated `csfmt_rts_data_v1`.

- ...:

  Passed to the method.

- value:

  The value column.

- baseline_isoyears:

  The number of earlier years in the baseline.

- remove_last_isoyearweeks:

  It has no effect: the method never uses it.

- forecast_isoyearweeks:

  The number of weeks to add after the data, with the baseline median as
  forecast and the status `"forecast"`.

- value_naming_prefix:

  The start of the new column names: `"from_numerator"` is `value`
  without its last `_<word>`, `"generic"` is `"value"`, and any other
  string is used as written.

- remove_training_data:

  If `TRUE`, drop the `"training"` weeks.

- measure:

  The draw matrix to compare with the limit.

## Value

The v1 method returns `x` with the forecast weeks added, and:

- `<value>_status`, a factor with the levels `"training"`, `"forecast"`,
  `"null"` and `"high"`,

- `*_forecasted_*`, the value or the forecast, and a logical forecast
  marker,

- `*_baseline_predinterval_*`, the 0.5%, 50% and 99.5% quantiles of the
  baseline normal.

The `csfmt_rts_data_v3` method always stops with an error.

The ensemble method returns `x` with a draw matrix
`<measure>_hlmstatus`: 1 for `null`, 2 for `high`, and `NA` with no
limit, with a `levels` attribute. It adds `hlm_threshold`, the limit, to
`$data` by reference, so the input ensemble gets it too.

## Details

The baseline of a week is the values 52, 104, and so on up to
`52 * baseline_isoyears` rows back, each with its two neighbours. The
limit is `qnorm(0.995, mean, sd)` of those values. A week that lacks any
of them gets none. A year back is 52 rows, so across a 53-week ISO year
the baseline is one week off. The limit is treated as known.

## The deprecated csfmt_rts_data_v1 method

`signal_detection_hlm.csfmt_rts_data_v1()` is **deprecated**. It still
works and gives no warning. New work SHOULD run the ensemble method
before
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md):

    ens <- nowcast_delay_ecdf_v1(triangle, max_delay_days = 35)
    ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")
    out <- ens_collapse(ens, heal = TRUE)

**The replacement is not a drop-in.** The v1 method takes `value`,
`remove_last_isoyearweeks`, `forecast_isoyearweeks` and
`value_naming_prefix`, where the ensemble method takes a draw matrix,
`measure`. The v1 method returns a label per week. The ensemble method
classifies every draw, so after the collapse it gives the share of draws
above the limit.

The v1 method labels a week `high` when its value is above the limit,
and `training` when it has no baseline.

## Why the csfmt_rts_data_v3 method is an error

A `csfmt_rts_data_v3` is the collapsed output of the pipeline. It holds
quantiles, not draws, so no per-draw comparison can come from it. Run
the detection before the collapse:

    ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")  # before
    out <- ens_collapse(ens, heal = TRUE)                              # then collapse

## The csfmt_ensemble_v3 method

The baseline uses the median of the draws of each earlier week. A draw
at or above the limit is `high`, and otherwise `null`. After
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
`<measure>_hlmstatus_prob_high` is the share of draws at or above the
limit. That share describes the nowcast uncertainty. It is not a
p-value, a posterior probability or a false-alarm rate.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 7, and
[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md)
on which method to use.

Other ensemble operations:
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md),
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
[`mem_thresholds_v1()`](https://niphr.github.io/csalert/reference/mem_thresholds_v1.md),
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)

## Examples

``` r
# the deprecated csfmt_rts_data_v1 method
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
