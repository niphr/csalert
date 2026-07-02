# Probability -\> controlled-vocabulary quantile label

\`0.025 -\> "q02x5"\`, \`0.5 -\> "q50x0"\`, \`0.975 -\> "q97x5"\`,
\`0.005 -\> "q00x5"\`. Two integer-percent digits, then \`x\`, then one
decimal-percent digit.

## Usage

``` r
q_label(p)
```

## Arguments

- p:

  Numeric vector of probabilities in \[0, 1\].

## Value

Character vector of quantile labels.

## Examples

``` r
q_label(c(0.025, 0.5, 0.975))
#> [1] "q02x5" "q50x0" "q97x5"
```
