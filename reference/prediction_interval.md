# Prediction thresholds

Prediction thresholds

## Usage

``` r
prediction_interval(object, newdata, alpha = 0.05, z = NULL, ...)
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

- ...:

  dots

## Value

A \`data.table\` with one row per row of \`newdata\` and the columns
\`lower\`, \`point\` and \`upper\`, giving the two-sided prediction
interval and the point estimate on the response scale.
