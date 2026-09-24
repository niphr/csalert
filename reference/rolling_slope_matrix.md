# Rolling regression slope down every column of a matrix

Fits `y ~ 1 + t`, with `t` from 1 to `width`, to each window of `width`
rows in every column. It is the kernel of the ensemble method of
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md).

## Usage

``` r
rolling_slope_matrix(
  Y,
  width,
  family = c("identity", "quasipoisson", "binomial"),
  prior_weights = NULL,
  tol = 1e-10,
  maxit = 25L
)
```

## Arguments

- Y:

  A numeric matrix, rows = weeks in time order, columns = draws.

- width:

  The window width in rows, at least 2.

- family:

  `"identity"` is ordinary least squares. `"quasipoisson"` is a log link
  and `"binomial"` a logit link, and for those `beta1` is on the link
  scale.

- prior_weights:

  The binomial denominators, a matrix the shape of `Y` or with one
  column. Only `family = "binomial"` takes it, and it needs it.

- tol:

  The iteration stops when no coefficient moves more than `tol`.

- maxit:

  The most iterations. A window that still moves more than `tol` did not
  converge.

## Value

A list of four matrices, each the shape of `Y`: `beta0`, `beta1`, `se`
and `converged`. `se` is the standard error of `beta1`, a Wald standard
error under IRLS. The logical `converged` is `NA` on the first
`width - 1` rows.

## Details

Row `i` holds the fit of the window that ends on row `i`, so the first
`width - 1` rows are `NA`. The identity family has a closed form. The
other two families run iteratively reweighted least squares (IRLS) on
every window at once. A window with complete or quasi-complete
separation cannot converge: its `beta0`, `beta1` and `se` are `NA`, and
one warning gives the count.

## One deliberate difference from glm

The function agrees with
[`stats::glm()`](https://rdrr.io/r/stats/glm.html) except on an all-zero
window. There it returns `NA`, and
[`stats::glm()`](https://rdrr.io/r/stats/glm.html) returns a slope of 0.
[`stats::glm()`](https://rdrr.io/r/stats/glm.html) stops on the relative
change in deviance, which is 0 from the first step. This function stops
on the coefficient step, which never settles, because the intercept goes
to `-Inf`. An all-zero window identifies no slope, and `NA` says so.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 5.

Other short-term trend functions:
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md),
[`short_term_trend_sts_v1()`](https://niphr.github.io/csalert/reference/short_term_trend_sts_v1.md)

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

# the later rows find the slope, one estimate per draw
round(rs$beta1[8:10, ], 2)
#>      [,1] [,2] [,3] [,4]
#> [1,] 2.25 1.95 1.36 2.40
#> [2,] 2.44 2.36 1.74 2.49
#> [3,] 1.75 2.17 2.27 2.46

# `se` is the OLS standard error of the slope
round(rs$se[10, ], 2)
#> [1] 0.18 0.20 0.39 0.20

# a log link: counts that rise by 0.2 per week on the log scale
N <- matrix(rpois(40, rep(exp(1 + 0.2 * 1:10), 4)), nrow = 10)
round(rolling_slope_matrix(N, width = 4, family = "quasipoisson")$beta1[10, ], 2)
#> [1] 0.24 0.45 0.19 0.35
```
