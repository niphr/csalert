# Prediction interval for new data from a Poisson or quasi-Poisson glm

Internal. It combines the dispersion of the fit with the standard error
of the fitted mean, on the power scale that `skewness_transform` names.

## Usage

``` r
# S3 method for class 'glm'
prediction_interval(
  object,
  newdata,
  alpha = 0.05,
  z = NULL,
  skewness_transform = "none",
  ...
)
```

## Arguments

- object:

  A `glm` of family `poisson` or `quasipoisson`.

- newdata:

  A data.frame of covariates.

- alpha:

  The two-sided significance level.

- z:

  The normal quantile. When given, it replaces `alpha`.

- skewness_transform:

  The power scale: `"none"`, `"1/2"` or `"2/3"`.

- ...:

  Not used, but the generic has it.

## Value

A `data.table` with one row per row of `newdata`: `lower`, `point` and
`upper`, on the response scale. All three are `NA_real_` when any step
gives a warning or an error.
