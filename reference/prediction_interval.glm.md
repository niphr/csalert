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

## Value

A \`data.table\` with one row per row of \`newdata\` and the columns
\`lower\`, \`point\` and \`upper\`, giving the two-sided prediction
interval and the point estimate on the response scale. All three columns
are \`NA_real\_\` if the underlying \`stats::predict\` call raises a
warning or an error.
