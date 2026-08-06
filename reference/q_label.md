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

## Details

The format is lossy in two ways. It holds one decimal-percent digit, so
a finer probability is rounded (\`0.0125 -\> "q01x2"\`). And it holds
exactly two integer-percent digits, so \`p = 1\` produces the
three-digit \`"q100x0"\`, which \[q_value\] cannot read back. Keep \`p\`
on the 0.001 grid and strictly below 1.

## See also

\[q_value\] reads these labels back, for \`p \< 1\`.
[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
calls this function in its naming-grammar section, and every \`\_qNNxN\`
column it prints was labelled by it.

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

# limit 2: p = 1 produces a three-digit label q_value() returns NA for
q_label(1)
#> [1] "q100x0"
q_value(q_label(1))
#> [1] NA
```
