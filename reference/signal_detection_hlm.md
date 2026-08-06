# Detect signals using the historical limits method

Flags weeks where the observed value is unusually high compared with a
baseline built from the same weeks in previous years. For each week, a
baseline mean and standard deviation are computed from the surrounding
weeks in each of the previous `baseline_isoyears` years. The surrounding
weeks are `week - 1`, `week` and `week + 1`. A week is flagged as
`"high"` when its value exceeds the upper (99.5%) baseline prediction
interval.

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

  Data object.

- ...:

  Not in use.

- value:

  Character of name of value.

- baseline_isoyears:

  Years of history used for the baseline.

- remove_last_isoyearweeks:

  Number of isoyearweeks you want to remove at the end (due to
  unreliable data).

- forecast_isoyearweeks:

  Number of isoyearweeks you want to forecast into the future.

- value_naming_prefix:

  "from_numerator", "generic", or a custom prefix.

- remove_training_data:

  Boolean. If TRUE, removes the training data (i.e. the early weeks that
  have no baseline) from the returned dataset.

- measure:

  The \`\$draws\` measure to detect signals on.

## Value

The original csfmt_rts_data_v1 dataset with extra columns. `*_status` is
a factor with levels c("training", "forecast", "null", "high"), flagging
weeks above the baseline. `*_forecasted*` holds the observed value, or
the baseline median for forecast weeks. `*_baseline_predinterval_*`
holds the lower (0.5%), median (50%) and upper (99.5%) baseline
prediction interval.

The \`csfmt_rts_data_v3\` method always errors: see the section below.

The \`csfmt_ensemble_v3\` with a per-draw exceedance column added to
\`\$draws\` for \`measure\`. The column is 1 where the draw exceeds its
HLM baseline threshold and 0 otherwise, so the exceedance probability
falls out of the quantile collapse. Weeks without a full baseline are
NA.

## Deprecated (the csfmt_rts_data_v1 method)

\`signal_detection_hlm.csfmt_rts_data_v1\` is \*\*deprecated\*\*. It
belongs to the pre-ensemble architecture, in which each analysis stage
read and wrote a \`cstidy\` table. The current architecture makes
\`csfmt_ensemble_v3\` the analysis substrate: every stage takes the
ensemble and returns the ensemble, and \[ens_collapse\] is terminal.

It still works and emits no warning, so existing pipelines are
undisturbed. New work SHOULD call \`signal_detection_hlm()\` on the
\*\*ensemble\*\*, before \`ens_collapse()\`:

    ens <- nowcast_quasipoisson_v1(triangle, max_delay = 5)
    ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")
    out <- ens_collapse(ens, heal = TRUE)

\*\*The replacement is not a drop-in.\*\* The two methods differ in
interface and in output, not only in the class they accept:

- the v1 method takes \`value\`, \`remove_last_isoyearweeks\`,
  \`forecast_isoyearweeks\` and \`value_naming_prefix\`. The ensemble
  method takes one \`measure\` naming a \`\$draws\` matrix and
  \`baseline_isoyears\`.

- the v1 method returns a factor status column with \`training\` /
  \`forecast\` / \`null\` / \`high\` levels plus baseline
  prediction-interval columns. The ensemble method classifies every DRAW
  against the baseline limit, so the result is an exceedance PROBABILITY
  after the collapse, not a label.

Migrating is therefore a rewrite of the call site, and the output is a
different kind of quantity. See
[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs the ensemble method as stage 7 of its pipeline.

## Why there is no csfmt_rts_data_v3 method

\`csfmt_rts_data_v3\` is the COLLAPSED output of the pipeline, and the
collapse is terminal. It carries quantiles, not draws, so the per-draw
exceedance this function computes cannot be produced from it. Calling
\`signal_detection_hlm()\` on one is always a mistake, so the method
exists only to say so:

    ens <- signal_detection_hlm(ens, measure = "numerator_nowcasted")  # before
    out <- ens_collapse(ens, heal = TRUE)                              # then collapse

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs the ensemble method as stage 7 of its pipeline. The example
below is the only worked demonstration of the \`csfmt_rts_data_v1\`
method, which is deprecated.
[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md)
explains which of the two generations to use.

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
