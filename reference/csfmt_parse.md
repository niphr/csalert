# Parse a csfmt measure column name into components (inverse of \[csfmt_var\])

Parse a csfmt measure column name into components (inverse of
\[csfmt_var\])

## Usage

``` r
csfmt_parse(varname)
```

## Arguments

- varname:

  Character scalar column name.

## Value

Named list with the components that were present (e.g. \`measure\`,
\`role\`, \`q\`, \`denom\`, \`per\`), i.e. the inverse of \[csfmt_var\].

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
```
