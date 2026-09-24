# Read the probability in a quantile label

Reads a label that
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md)
wrote: `q`, two digits, `x` and one digit. Any other string gives `NA`.

## Usage

``` r
q_value(label)
```

## Arguments

- label:

  A character vector of labels, for example `"q02x5"`.

## Value

A numeric vector of probabilities.

## Details

`q_value(q_label(p))` returns `p` only for a `p` on the 0.001 grid and
below 1. Every probability that the package uses is on that grid.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
whose naming-grammar section shows the round trip.

Other naming grammar functions:
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md),
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md)

## Examples

``` r
q_value(c("q02x5", "q50x0", "q97x5"))
#> [1] 0.025 0.500 0.975

# a string that is not a label gives NA, and so does the three-digit q100x0
q_value(c("q100x0", "not_a_label"))
#> [1] NA NA
```
