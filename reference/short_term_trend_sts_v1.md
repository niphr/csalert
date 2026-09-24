# Short-term trend alarms on a surveillance sts object

Sets an alarm where a rolling quasi-Poisson regression finds a
significant rise, in each column of a
[`surveillance::sts`](https://rdrr.io/pkg/surveillance/man/sts-class.html)
object, after Benedetti (2019) <doi:10.5588/pha.19.0002>. It has not
changed since 2024-06-24.

## Usage

``` r
short_term_trend_sts_v1(sts, control = list(w = 5, alpha = 0.05))
```

## Arguments

- sts:

  A
  [`surveillance::sts`](https://rdrr.io/pkg/surveillance/man/sts-class.html)
  object.

- control:

  A list with `w`, the window width, and `alpha`, the significance
  level. A missing element takes its default.

## Value

`sts` with its alarms set.

## Details

Each time point gets the fit of `observed ~ trend + log(population)`, by
[`glm2::glm2()`](https://rdrr.io/pkg/glm2/man/glm2.html), on the `w`
time points that end there. Its alarm is 1 when the slope is positive
with a p-value below `alpha`, and 0 otherwise. The first `w - 1` time
points keep their alarm.

## See also

[`vignette("csalert", package = "csalert")`](https://niphr.github.io/csalert/articles/csalert.md),
which explains the deprecated trend methods. The `csfmt_rts_data_v1`
method of
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
is the table form of this function.

Other short-term trend functions:
[`rolling_slope_matrix()`](https://niphr.github.io/csalert/reference/rolling_slope_matrix.md),
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)

## Examples

``` r
d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1
d <- d[granularity_time=="isoyearweek"]
sts <- surveillance::sts(
  observed = d$hospitalization_with_covid19_as_primary_cause_n, # weekly counts
  start = c(d$isoyear[1], d$isoweek[1]), # the first week of the series
  frequency = 52
)
x <- csalert::short_term_trend_sts_v1(
  sts,
  control = list(
    w = 5,
    alpha = 0.05
  )
)
plot(x)
```
