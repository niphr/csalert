# Determine the short term trend of a timeseries

Fits a quasi-Poisson regression over a moving window of recent weeks and
classifies the short-term trend of the numerator (optionally per a
denominator) as increasing or not, together with an estimated doubling
time. The method is based upon a published analytics strategy by
Benedetti (2019) \<doi:10.5588/pha.19.0002\>.

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
  propagate_slope_error = FALSE,
  n_sim = 1000L,
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

  Rolling window width in isoyearweeks (\>= 2).

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

- measure:

  Character: the \`\$draws\` measure to compute the trend on.

- propagate_slope_error:

  Logical. If \`TRUE\`, add the OLS slope's own sampling error to each
  draw (\`beta1 + se \* t\_(width-2)\`) before forming the growth rate,
  so the trend interval reflects the uncertainty of the slope estimate
  and not only the uncertainty of the level. Defaults to \`FALSE\`,
  which keeps the published numbers unchanged. Note the degrees of
  freedom are \`trend_isoyearweeks - 2\`: at the default width of 3 that
  is 1, a Cauchy, so widen the window before enabling this.

- n_sim:

  Integer. Draw-axis width used for the slope-error perturbation when
  the incoming ensemble is degenerate (a single passthrough draw, which
  has no draw axis to carry the uncertainty). Ignored when the ensemble
  already has draws, and when \`propagate_slope_error\` is \`FALSE\`.

## Value

The original csfmt_rts_data_v1 dataset with extra columns.
\*\_trend\*\_status contains a factor with levels c("training",
"forecast", "decreasing", "null", "increasing"), while
\*\_doublingdays\* contains the expected number of days before the
numerator doubles.

The \`csfmt_rts_data_v3\` method always errors: see the section below.

The \`csfmt_ensemble_v3\` with per-draw short-term-trend columns added
to \`\$draws\` for \`measure\` (the rolling slope/level and a
P(increasing)), ready for the quantile collapse.

## Deprecated (the csfmt_rts_data_v1 method)

\`short_term_trend.csfmt_rts_data_v1\` is \*\*deprecated\*\*. It belongs
to the pre-ensemble architecture, in which each analysis stage read and
wrote a \`cstidy\` table. The current architecture makes
\`csfmt_ensemble_v3\` the analysis substrate: every stage takes the
ensemble and returns the ensemble, and \[ens_collapse\] is terminal.

It still works and emits no warning, so existing pipelines are
undisturbed. New work should call \`short_term_trend()\` on the
\*\*ensemble\*\*, before \`ens_collapse()\`:

    ens <- nowcast_quasipoisson_v1(triangle, max_delay = 5)
    ens <- short_term_trend(ens, measure = "numerator_nowcasted")
    out <- ens_collapse(ens, heal = TRUE)

\*\*The replacement is not a drop-in.\*\* The two methods differ in
interface and in output, not only in the class they accept:

- the v1 method takes \`numerator\`, \`denominator\`, \`prX\` and the
  \`\*\_naming_prefix\` arguments. The ensemble method takes one
  \`measure\` naming a \`\$draws\` matrix; a rate is built beforehand
  with \[ens_add_rate\].

- the v1 method fits a quasi-Poisson log-link model and returns a factor
  status column plus a doubling time. The ensemble method computes a
  per-draw OLS slope, a growth rate and a P(increasing), and returns no
  classification at all.

Migrating is therefore a rewrite of the call site, and the numbers will
not match. See
[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md),
which runs the ensemble method as stage 5 of its pipeline.

## Why there is no csfmt_rts_data_v3 method

\`csfmt_rts_data_v3\` is the COLLAPSED output of the pipeline, and the
collapse is terminal. It carries quantiles, not draws, so a per-draw
trend and a P(increasing) cannot be recovered from it. Calling
\`short_term_trend()\` on one is always a mistake, so the method exists
only to say so:

    ens <- short_term_trend(ens, measure = "numerator_nowcasted")  # before
    out <- ens_collapse(ens, heal = TRUE)                          # then collapse

## See also

[`vignette("short_term_trend", package = "csalert")`](https://niphr.github.io/csalert/articles/short_term_trend.md),
which runs this function on one location and then on every Norwegian
county.
[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md)
runs the ensemble method as the final stage of its pipeline, on the
output of a nowcast.

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
