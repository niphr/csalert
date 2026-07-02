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
