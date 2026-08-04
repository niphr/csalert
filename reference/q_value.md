# Quantile label -\> probability

Reads back a label written by \[q_label\]. The pattern accepted is
exactly two integer-percent digits, \`x\`, then one decimal digit. Any
string that does not match returns \`NA\` rather than erroring.

## Usage

``` r
q_value(label)
```

## Arguments

- label:

  Character vector of quantile labels, e.g. "q02x5".

## Value

Numeric vector of probabilities; \`NA\` for an unparseable label.

## Details

The round trip \`q_value(q_label(p))\` returns \`p\` only when \`p\` is
expressible in that format, i.e. a probability on the 0.001 grid
below 1. \`q_label()\` rounds anything finer (\`0.0125\` becomes
\`"q01x2"\`, which reads back as \`0.012\`), and \`q_label(1)\` gives
the three-digit \`"q100x0"\`, which returns \`NA\`. Every probability
the package itself uses is on the grid.

## See also

\[q_label\] writes these labels. Neither package vignette calls this
function by name. It is how generic tooling recovers the probability
behind a \`\_qNNxN\` column.

Other naming grammar functions:
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md),
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md)

## Examples

``` r
q_value(c("q02x5", "q50x0", "q97x5"))
#> [1] 0.025 0.500 0.975

# unparseable labels come back NA, including the three-digit q100x0
q_value(c("q100x0", "not_a_label"))
#> [1] NA NA
```
