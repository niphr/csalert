# Quantile label -\> probability (inverse of \[q_label\])

Quantile label -\> probability (inverse of \[q_label\])

## Usage

``` r
q_value(label)
```

## Arguments

- label:

  Character vector of quantile labels, e.g. "q02x5".

## Value

Numeric vector of probabilities.

## Examples

``` r
q_value(c("q02x5", "q50x0", "q97x5"))
#> [1] 0.025 0.500 0.975
```
