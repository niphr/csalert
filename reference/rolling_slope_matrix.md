# Rolling regression slope over a weeks x draws matrix

Fits \`y ~ 1 + t\` over each window (length \`width\`, local time index
\`1..width\`) independently down every column. Returns matrices of the
same shape; the leading \`width-1\` rows of each column are NA.

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

  Numeric matrix, rows = time (ordered), columns = draws.

- width:

  Window width (\>= 2).

- family:

  Error family and link. \`"identity"\` is the default. It is the
  closed-form ordinary least squares fit on \`Y\`. \`"quasipoisson"\` is
  a log link and \`"binomial"\` is a logit link. Both of those run
  iteratively reweighted least squares, so \`beta1\` is a slope on the
  link scale.

- prior_weights:

  Numeric matrix of binomial denominators, shaped like \`Y\` or holding
  one column that is recycled across the draws. \`family = "binomial"\`
  needs it, and the other two families reject it.

- tol:

  Convergence tolerance. The iteration stops once no coefficient of any
  window moves further than \`tol\`.

- maxit:

  Maximum number of iterations. A window whose coefficients still move
  further than \`tol\` at iteration \`maxit\` did not converge.

## Value

List of matrices: \`beta0\`, \`beta1\`, \`se\`, \`converged\`. \`se\` is
the standard error of \`beta1\`. Under the two GLM families it is a Wald
standard error. \`converged\` is logical. It is \`NA\` on the leading
\`width-1\` rows, which hold no window. \`beta0\`, \`beta1\` and \`se\`
are \`NA_real\_\` wherever \`converged\` is \`FALSE\`. The closed-form
identity family solves every complete window, so its \`converged\` is
\`TRUE\` throughout.

## Details

A window with complete or quasi-complete separation drives the slope to
infinity, so IRLS cannot converge. \`beta0\`, \`beta1\` and \`se\` are
then \`NA_real\_\`, and the function warns once with the count.

## A deliberate divergence from glm

An all-zero window returns \`NA\` here. \`stats::glm()\` returns a slope
of 0 on the same window. The two use different convergence rules.
\`stats::glm()\` stops on the relative change in the deviance, which is
0 for an all-zero window from the first iteration. This kernel stops on
the coefficient step, and that step never settles: the intercept marches
to \`-Inf\` as the fitted mean goes to 0. Agreement with
\`stats::glm()\` is the contract of this function, so the divergence is
deliberate, and this is the one case of it. An all-zero window
identifies no slope, and \`NA\` says so.

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

# a log link instead: counts rising at 0.2 per week on the log scale
N <- matrix(rpois(40, rep(exp(1 + 0.2 * 1:10), 4)), nrow = 10)
round(rolling_slope_matrix(N, width = 4, family = "quasipoisson")$beta1[10, ], 2)
#> [1] 0.24 0.45 0.19 0.35
```
