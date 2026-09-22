# Censor a reporting triangle to what was known "as of" a past date

Keeps only cells reported on or before \`as_of\` and rebuilds the
triangle. Its as-of boundary and delay structure are then exactly what
an engine would have seen on that date. The basis for replay-based
backtesting.

## Usage

``` r
nowcast_censor(triangle, as_of)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- as_of:

  A \`Date\`. Cells reported after it are dropped. A character, a
  number, a factor and an \`IDate\` each error. The check is strict
  because R reads \`reporting date \<= as_of\` from the type of
  \`as_of\`. A number is a day count since 1970-01-01, so \`as_of =
  18262\` censors to 2020-01-01 and reports nothing wrong. A character
  goes through \`as.Date()\`, so \`"2020-11"\` errors inside
  \`charToDate()\` with a message that never names \`as_of\`.

## Value

A \`csfmt_reporting_triangle_v3\` censored to \`as_of\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
calls this function directly in its validation stage, to rebuild what
was known on an earlier date.
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
censors for you when you do not need the censored triangle itself.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday
monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# rewind to what was known nine weeks earlier
past <- nowcast_censor(tri, as_of = as.Date("2023-01-02") + 7 * 30 + 6)
c(now = attr(tri, "as_of"), then = attr(past, "as_of"))
#>          now         then 
#> "2023-10-05" "2023-08-03" 
c(rows_now = nrow(tri), rows_then = nrow(past))
#>  rows_now rows_then 
#>       117        90 
```
