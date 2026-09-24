# Write a probability as a quantile label

Writes `q`, two integer-percent digits, `x` and one decimal-percent
digit, so `0.025` becomes `"q02x5"`.

## Usage

``` r
q_label(p)
```

## Arguments

- p:

  A numeric vector of probabilities.

## Value

A character vector of labels, with `NA` for `NA`.

## Details

The label loses information in two ways. A finer probability is rounded:
`0.0125` becomes `"q01x2"`. And `p = 1` gives `"q100x0"`, which
[`q_value()`](https://niphr.github.io/csalert/reference/q_value.md)
cannot read. Keep `p` on the 0.001 grid and below 1.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
whose naming-grammar section shows both limits.

Other naming grammar functions:
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md),
[`q_value()`](https://niphr.github.io/csalert/reference/q_value.md)

## Examples

``` r
q_label(c(0.025, 0.5, 0.975))
#> [1] "q02x5" "q50x0" "q97x5"

# limit 1: a probability finer than one decimal percent is rounded
q_value(q_label(0.0125))
#> [1] 0.012

# limit 2: p = 1 gives a three-digit label, and q_value() returns NA for it
q_label(1)
#> [1] "q100x0"
q_value(q_label(1))
#> [1] NA
```
