# Parse a csfmt measure column name into components

Reads a column name written by \[csfmt_var\] back into its parts. It
strips the trailing coordinates, then a role, then a \`\_vs\_\<denom\>\`
segment, and whatever is left is the measure.

## Usage

``` r
csfmt_parse(varname)
```

## Arguments

- varname:

  Character scalar column name.

## Value

Named list with the components that were present (e.g. \`measure\`,
\`role\`, \`q\`, \`denom\`, \`per\`).

## Where it does not invert csfmt_var

The parse is a right-to-left strip against a fixed role vocabulary, so
it cannot tell which of several role-looking segments was the role. On
the package's own rate name it gets the denominator wrong:

    csfmt_var("numerator_nowcasted", denom = "denominator_nowcasted", per = 100)
    #> "numerator_nowcasted_vs_denominator_nowcasted_pr100"
    csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")$denom
    #> "denominator"          # the denominator's own "_nowcasted" was eaten as the role

Treat it as reliable for a single-role name such as
\`numerator_nowcasted_q50x0\`, and check the result whenever the measure
or the denominator itself ends in a role word.

## See also

\[csfmt_var\] writes these names.
[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md),
whose closing section parses a collapsed median column with this
function.

Other naming grammar functions:
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md),
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md),
[`q_value()`](https://niphr.github.io/csalert/reference/q_value.md)

## Examples

``` r
csfmt_parse("numerator_nowcasted_q50x0")
#> $measure
#> [1] "numerator"
#> 
#> $role
#> [1] "nowcasted"
#> 
#> $q
#> [1] 0.5
#> 

# the documented limit: a denominator that itself ends in a role word is
# truncated, because the role is stripped before the _vs_ segment is read
csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")
#> $measure
#> [1] "numerator_nowcasted"
#> 
#> $denom
#> [1] "denominator"
#> 
#> $role
#> [1] "nowcasted"
#> 
#> $per
#> [1] 100
#> 
```
