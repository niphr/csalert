# Split a measure column name into its parts

Reads a name that
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md)
wrote back into its parts. From the right, it removes a `_n` suffix, a
`_pr<per>` scale, a quantile label and a `_prob_<level>` level. It then
removes a role and `_vs_<denom>`, and the rest is the measure.

## Usage

``` r
csfmt_parse(varname)
```

## Arguments

- varname:

  The column name.

## Value

A named list of the parts that are present: `measure`, `denom`, `role`,
`q`, `level`, `per` and `suffix`, in that order.

## Details

The roles it knows are `observed`, `nowcasted`, `forecasted`, `trend`,
`baseline`, `status` and `hlmstatus`.

## Where it does not invert csfmt_var

The parse cannot tell which of two role words was the role. On the rate
name of the package, it gets the denominator wrong:

    csfmt_var("numerator_nowcasted", denom = "denominator_nowcasted", per = 100)
    #> "numerator_nowcasted_vs_denominator_nowcasted_pr100"
    csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")$denom
    #> "denominator"   # "_nowcasted" of the denominator was read as the role

The parse is reliable for a name with one role word, such as
`numerator_nowcasted_q50x0`. Check the result when the measure or the
denominator ends in a role word.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
whose naming-grammar section shows this limit.

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

# the limit: the role is removed before the _vs_ part is read, so a
# denominator that ends in a role word loses that word
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
