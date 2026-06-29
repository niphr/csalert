# Prediction thresholds

Prediction thresholds

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

  Object

- newdata:

  New data

- alpha:

  Two-sided alpha (e.g 0.05)

- z:

  Similar to `alpha` (e.g. z=1.96 is the same as alpha=0.05)

- skewness_transform:

  "none", "1/2", "2/3"

- ...:

  dots
