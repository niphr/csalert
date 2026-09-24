# Estimate the short-term trend of a series

The `csfmt_ensemble_v3` method fits a line through a rolling window of
weeks in every draw. The deprecated `csfmt_rts_data_v1` method fits a
rolling quasi-Poisson regression to a table, after Benedetti (2019)
<doi:10.5588/pha.19.0002>.

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

# S3 method for class 'csfmt_rts_data_v3'
short_term_trend(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
short_term_trend(
  x,
  measure,
  trend_isoyearweeks = 3,
  n_sim = 1000L,
  family = c("identity", "quasipoisson", "binomial"),
  denominator = NULL,
  error_reference = c("auto", "normal", "t"),
  ...
)
```

## Arguments

- x:

  A `csfmt_ensemble_v3`, or a deprecated `csfmt_rts_data_v1`.

- ...:

  Passed to the method.

- numerator:

  The count column.

- denominator:

  For `csfmt_rts_data_v1`, an optional denominator column. For
  `csfmt_ensemble_v3`, the draw matrix of the binomial denominator,
  which `family = "binomial"` needs and the other families reject.
  `measure` MUST then be a proportion.

- prX:

  The scale of the rate `numerator / denominator`, such as `100`. It MAY
  hold more than one scale.

- trend_isoyearweeks:

  The width of the rolling window, in weeks. The ensemble method needs
  at least 3, or 2 with `family = "binomial"`. The v1 method needs at
  least 2.

- remove_last_isoyearweeks:

  The number of latest weeks to leave out of the fit. They get the
  status `"forecast"`.

- forecast_isoyearweeks:

  The number of weeks to forecast after the data.

- numerator_naming_prefix:

  The start of the new column names. `"from_numerator"` is the numerator
  name without its last `_<word>`, and `"generic"` is `"numerator"`. Any
  other string is used as written.

- denominator_naming_prefix:

  The same for the denominator.

- statistics_naming_prefix:

  `"universal"` names the columns `<prefix>_trend0_<days>_status` and
  `<prefix>_doublingdays0_<days>`, with
  `<days> = 7 * trend_isoyearweeks - 1`. `"from_numerator_and_prX"` adds
  the numerator suffix, or `_pr<prX>` with a denominator.

- remove_training_data:

  If `TRUE`, drop the first `trend_isoyearweeks - 1` rows, which have no
  window.

- include_decreasing:

  If `FALSE`, the levels are `"training"`, `"forecast"`,
  `"notincreasing"` and `"increasing"`. If `TRUE`, they are
  `"training"`, `"forecast"`, `"decreasing"`, `"null"` and
  `"increasing"`.

- alpha:

  The significance level of the test on the slope.

- measure:

  The draw matrix to fit the trend to.

- n_sim:

  The number of draws to use when the ensemble has one draw, as the
  output of
  [`nowcast_passthrough_to_ensemble_v1()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_to_ensemble_v1.md)
  has.

- family:

  `"identity"` is ordinary least squares, with the growth rate
  `100 * beta1 / Y`. `"quasipoisson"` is a log link, and `"binomial"` a
  logit link that needs `denominator`. For those two, `beta1` is on the
  link scale. The growth rate is then `100 * (exp(beta1) - 1)`, a
  percent change per week, in the odds under `"binomial"`. A zero count
  needs no offset.

- error_reference:

  The distribution of the slope error. `"auto"` gives `"identity"` and
  `"quasipoisson"` a t on `trend_isoyearweeks - 2` degrees of freedom,
  the residual degrees of freedom of their dispersion. It gives
  `"binomial"` a normal. At width 3 that t is a Cauchy, with heavy
  tails. Use `"normal"` to match
  [`stats::confint()`](https://rdrr.io/r/stats/confint.html), which
  profiles the deviance against an asymptotic chi-squared.

## Value

The v1 method returns `x` with the forecast weeks added. The new columns
are the status, the doubling time in days, the forecast with its 2.5%
and 97.5% limits, and a logical forecast marker. With a denominator, it
also adds the forecast denominator and rates.

The `csfmt_rts_data_v3` method always stops with an error.

The ensemble method returns `x` with the draw matrices
`<measure>_trend_beta1`, the slope per week, and `<measure>_trend_gr`,
the growth rate. It adds `<measure>_trend_increasing_pr`, the share of
draws with a positive slope, to `$data` by reference, so the input
ensemble gets it too.

## The deprecated csfmt_rts_data_v1 method

`short_term_trend.csfmt_rts_data_v1()` is **deprecated**. It still works
and gives no warning. New work SHOULD run the ensemble method before
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md):

    ens <- nowcast_delay_ecdf_v1(triangle, max_delay_days = 35)
    ens <- short_term_trend(ens, measure = "numerator_nowcasted")
    out <- ens_collapse(ens, heal = TRUE)

**The replacement is not a drop-in.** The v1 method takes `numerator`,
`denominator`, `prX` and the `*_naming_prefix` arguments. The ensemble
method takes one draw matrix, `measure`. The v1 method returns a status
and a doubling time from a quasi-Poisson log-link fit. The ensemble
method returns a slope, a growth rate and the share of draws with a
positive slope. So the call changes, and the numbers do not match.

The v1 method needs `granularity_time == "isoyearweek"`. A window is
`increasing` when its slope is positive with a p-value at most `alpha`.

## Why the csfmt_rts_data_v3 method is an error

A `csfmt_rts_data_v3` is the collapsed output of the pipeline. It holds
quantiles, not draws, so no per-draw trend can come from it. Run the
trend before the collapse:

    ens <- short_term_trend(ens, measure = "numerator_nowcasted")  # before
    out <- ens_collapse(ens, heal = TRUE)                          # then collapse

## The csfmt_ensemble_v3 method

In every draw, the method fits a line to the window of
`trend_isoyearweeks` weeks that ends on each week, with
[`rolling_slope_matrix()`](https://niphr.github.io/csalert/reference/rolling_slope_matrix.md).
The first `trend_isoyearweeks - 1` weeks of each series get `NA`.

It then adds the sampling error of the slope to each draw,
`beta1 + se * e`, with `e` from the distribution that `error_reference`
names. So a settled week, with the same count in every draw, still gets
an interval. The method returns no increasing label: choose your own
cut-off on the share of draws with a positive slope.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 5, and
[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md)
on which method to use.

Other ensemble operations:
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md),
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
[`mem_thresholds_v1()`](https://niphr.github.io/csalert/reference/mem_thresholds_v1.md),
[`signal_detection_hlm()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)

Other short-term trend functions:
[`rolling_slope_matrix()`](https://niphr.github.io/csalert/reference/rolling_slope_matrix.md),
[`short_term_trend_sts_v1()`](https://niphr.github.io/csalert/reference/short_term_trend_sts_v1.md)

## Examples

``` r
# the ensemble method: 10 weeks x 200 draws of a rising count
set.seed(1)
ens <- csfmt_ensemble_v3(
  data.table::data.table(
    isoyearweek = sprintf("2023-%02d", 1:10),
    location_code = "nation",
    age = "total"
  ),
  id_cols = c("location_code", "age"),
  draws = list(numerator_nowcasted = matrix(rpois(2000, 20 + 3 * 1:10), 10))
)
ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)
names(ens$draws)
#> [1] "numerator_nowcasted"             "numerator_nowcasted_trend_beta1"
#> [3] "numerator_nowcasted_trend_gr"   

# the share of draws with a positive slope; the first 4 weeks have no window
ens$data[, .(isoyearweek, numerator_nowcasted_trend_increasing_pr)]
#>     isoyearweek numerator_nowcasted_trend_increasing_pr
#>          <char>                                   <num>
#>  1:     2023-01                                      NA
#>  2:     2023-02                                      NA
#>  3:     2023-03                                      NA
#>  4:     2023-04                                      NA
#>  5:     2023-05                                   0.915
#>  6:     2023-06                                   0.860
#>  7:     2023-07                                   0.870
#>  8:     2023-08                                   0.845
#>  9:     2023-09                                   0.855
#> 10:     2023-10                                   0.855

# the deprecated csfmt_rts_data_v1 method
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
