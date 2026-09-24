# Prediction interval for new data from a fitted model

Internal: the deprecated `csfmt_rts_data_v1` method of
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
uses it for its forecast.

## Usage

``` r
prediction_interval(object, newdata, alpha = 0.05, z = NULL, ...)
```

## Arguments

- object:

  A fitted model.

- newdata:

  A data.frame of covariates.

- alpha:

  The two-sided significance level.

- z:

  The normal quantile. When given, it replaces `alpha`: `z = 1.96`
  equals `alpha = 0.05`.

- ...:

  Passed to the method.

## Value

A `data.table` with one row per row of `newdata`: `lower`, `point` and
`upper`, on the response scale.
