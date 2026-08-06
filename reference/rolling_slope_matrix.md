# Rolling OLS slope over a weeks x draws matrix

Closed-form simple linear regression of each window (length \`width\`,
time index 1..width) applied independently down every column. Returns
matrices of the same shape; leading \`width-1\` rows of each column are
NA.

## Usage

``` r
rolling_slope_matrix(Y, width)
```

## Arguments

- Y:

  Numeric matrix, rows = time (ordered), columns = draws.

- width:

  Window width (\>= 2).

## Value

List of matrices: \`beta0\`, \`beta1\`, \`se\`.

## See also

Neither package vignette covers this function. It is the numeric kernel
behind the ensemble method of
[`short_term_trend`](https://niphr.github.io/csalert/reference/short_term_trend.md),
which is the function you normally want. Use this one when you have a
bare weeks x draws matrix and no ensemble.

## Examples

``` r
# 10 weeks x 4 draws, all rising at a true slope of 2 per week
set.seed(1)
Y <- matrix(rep(1:10, 4) * 2 + rnorm(40), nrow = 10)

rs <- rolling_slope_matrix(Y, width = 4)

# the first three rows have no complete window, so they are NA
head(rs$beta1, 3)
#>      [,1] [,2] [,3] [,4]
#> [1,]   NA   NA   NA   NA
#> [2,]   NA   NA   NA   NA
#> [3,]   NA   NA   NA   NA

# later rows recover the slope, one estimate per draw
round(rs$beta1[8:10, ], 2)
#>      [,1] [,2] [,3] [,4]
#> [1,] 2.25 1.95 1.36 2.40
#> [2,] 2.44 2.36 1.74 2.49
#> [3,] 1.75 2.17 2.27 2.46

# `se` is the OLS standard error of that slope
round(rs$se[10, ], 2)
#> [1] 0.18 0.20 0.39 0.20
```
