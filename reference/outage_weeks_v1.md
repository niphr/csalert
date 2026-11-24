# Find the old weeks of a reporting triangle with a reporting outage

Finds the old reference weeks whose early reports are a small share of
their count. In
[`delay_distribution_v1()`](https://niphr.github.io/csalert/reference/delay_distribution_v1.md),
such a week makes reporting look slower than it is.

## Usage

``` r
outage_weeks_v1(
  x,
  max_delay_days,
  early_days = 9L,
  min_weeks_back = 5L,
  frac = 0.5
)
```

## Arguments

- x:

  A `csfmt_reporting_triangle_v3` with one series. With more than one
  `time_series_id`, the function stops with an error that names the id
  columns of `x`.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`.

- early_days:

  The last delay day of the early reports. With the default 9, the early
  reports are those on delay days 0 to 9.

- min_weeks_back:

  A candidate is at least this many weeks older than the newest row.

- frac:

  A candidate is flagged when its share is below `frac` times the median
  share.

## Value

A data.table with one character column, `isoyearweek_reference`: the
flagged reference weeks, oldest first. It has zero rows when the
function flags no week.

## Details

The rows and `n_seen` are those of
[`delay_distribution_v1()`](https://niphr.github.io/csalert/reference/delay_distribution_v1.md).
A row is a candidate when all three hold:

- it is at least `min_weeks_back` weeks older than the newest row,

- its `n_seen` is more than `early_days`, and

- its count on delay days 0 to `max_delay_days - 1` is more than 0.

With fewer than 4 candidates, the function flags no week. Otherwise, the
share of a candidate is its early count divided by its count on delay
days 0 to `max_delay_days - 1`. The early count is the count on delay
days 0 to `early_days`. The function flags a candidate when its share is
below `frac` times the median share of the candidates.

The function does not choose a window of weeks. To look in a window,
filter `x` before the call. A triangle filtered with `[` keeps its as-of
date.

## See also

[`delay_distribution_v1()`](https://niphr.github.io/csalert/reference/delay_distribution_v1.md),
to estimate the delay distribution without the flagged weeks.

## Examples

``` r
monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
# week 2023-20 has an outage: most of its cases arrive on day 17
d[isoyearweek_reference == "2023-20", numerator := c(2L, 3L, 45L)]
#> Index: <isoyearweek_reference>
#>      isoyearweek_reference reporting_date numerator indicator_tag location_code
#>                     <char>         <Date>     <int>        <char>        <char>
#>   1:               2023-01     2023-01-05        26             x        nation
#>   2:               2023-01     2023-01-12        20             x        nation
#>   3:               2023-01     2023-01-19         8             x        nation
#>   4:               2023-02     2023-01-12        38             x        nation
#>   5:               2023-02     2023-01-19        16             x        nation
#>  ---                                                                           
#> 116:               2023-39     2023-10-05        20             x        nation
#> 117:               2023-39     2023-10-12         3             x        nation
#> 118:               2023-40     2023-10-05        20             x        nation
#> 119:               2023-40     2023-10-12        13             x        nation
#> 120:               2023-40     2023-10-19         4             x        nation
#>         age    sex
#>      <char> <char>
#>   1:  total  total
#>   2:  total  total
#>   3:  total  total
#>   4:  total  total
#>   5:  total  total
#>  ---              
#> 116:  total  total
#> 117:  total  total
#> 118:  total  total
#> 119:  total  total
#> 120:  total  total
d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

out <- outage_weeks_v1(tri, max_delay_days = 21)
out
#>    isoyearweek_reference
#>                   <char>
#> 1:               2023-20

# the delay distribution without the outage week
tri_ok <- tri[!isoyearweek_reference %in% out$isoyearweek_reference]
delay_distribution_v1(tri_ok, 21)[p > 0]
#>    delay day_after week_after          p
#>    <int>     <int>      <int>      <num>
#> 1:     3        -3         NA 0.58655725
#> 2:    10         4         NA 0.31371523
#> 3:    17        11         NA 0.09972752
```
