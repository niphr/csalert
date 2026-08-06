# csalert <a href="https://niphr.github.io/csalert/"><img src="man/figures/logo.png" align="right" width="120" /></a>

[![CRAN status](https://www.r-pkg.org/badges/version/csalert)](https://cran.r-project.org/package=csalert)
[![CRAN downloads](https://cranlogs.r-pkg.org/badges/csalert)](https://cran.r-project.org/package=csalert)

## Overview

[csalert](https://niphr.github.io/csalert/) helps create alerts from public health
surveillance data.

Weekly counts arrive late, so the newest weeks always look lower than they will end up.
Work therefore starts from a **reporting triangle**: the counts, plus the week each count
was reported in. A nowcast engine completes the weeks that are not fully reported yet and
returns Monte-Carlo draws rather than a single number. Rate, trend, MEM intensity and
baseline exceedance then each run on those draws and hand them back. The reporting
uncertainty therefore reaches the trend and the alert instead of stopping at the nowcast.
`ens_collapse()` reduces the draws to quantiles at the end, and that step is terminal.

`short_term_trend()` and `signal_detection_hlm()` also have older methods. Those methods
run directly on a weekly `cstidy` table and return a status label. They use the
quasi-Poisson strategy of Benedetti (2019),
[doi:10.5588/pha.19.0002](https://doi.org/10.5588/pha.19.0002).
**Those methods are deprecated.** They still work and emit no warning, but they take
different arguments, return a different shape, and give different numbers.

## Installation

``` r
# released version
install.packages("csalert")

# development version
pak::pak("niphr/csalert")
```

## Quick start

``` r
library(csalert)
library(data.table)

# counts, and the week each count was reported in
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
d <- data.table(
  isoyearweek_reference = w[i + rep(0:51, each = 3)],
  isoyearweek_reporting = w[i + rep(0:51, each = 3) + rep(0:2, 52)],
  numerator = rpois(156, c(40, 20, 8)),
  indicator_tag = "hospitalisation", location_code = "nation",
  age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 51]]

tri <- csfmt_reporting_triangle_v3(
  d, id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# complete the weeks still arriving, then measure direction on the draws
ens <- nowcast_quasipoisson_v1(tri, max_delay = 3, n_sim = 500)
ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)

# one tidy table at the end
res <- ens_collapse(ens, heal = TRUE)
res[, .(isoyearweek, numerator_nowcasted_q50x0,
        numerator_nowcasted_trend_increasing_pr)]
```

## Which function do I want?

| Goal | Function |
| --- | --- |
| Build the reference-by-reporting input format | `csfmt_reporting_triangle_v3()` |
| Fill in weeks that are not fully reported yet | `nowcast_quasipoisson_v1()` |
| Send an indicator through unchanged, without filling in | `nowcast_passthrough_to_ensemble_v1()` |
| Measure a nowcast's interval coverage and revision on replayed weeks | `nowcast_evaluate_v1()` |
| Measure how quickly cases arrive, within a chosen delay horizon | `reporting_completion_v1()` |
| Add a rate when a denominator exists | `ens_add_rate()` |
| Estimate recent direction, per draw | `short_term_trend()` |
| Classify weekly intensity against season-specific MEM thresholds | `mem_thresholds_v1()` |
| Flag counts that exceed a modelled historical baseline | `signal_detection_hlm()` |
| Turn Monte-Carlo draws into quantile columns | `ens_collapse()` |
| Check that a feed has rows, has its reference column, and is not stale | `qc_surveillance_data_v1()` |
| Diff every value column of this run against the previous run | `compare_results()` |
| Split that diff into settled-week changes and frontier status moves | `qc_week_over_week_v1()` |
| Make synthetic data to test a method on | `simulate_baseline_data()` |

`short_term_trend()` and `signal_detection_hlm()` dispatch on what you pass them. Give them
a `csfmt_ensemble_v3` and you get the current per-draw methods. Give them a
`csfmt_rts_data_v1` and you get the deprecated table methods. The extra arguments
`numerator`, `denominator`, `prX` and `include_decreasing` belong to that route only.

## Documentation

Full documentation is at <https://niphr.github.io/csalert/>: the
[function reference](https://niphr.github.io/csalert/reference/index.html), and two
articles. Start with
[Get started](https://niphr.github.io/csalert/articles/csalert.html), which says what
the package is for and which half of it is current. Then read
[The pipeline](https://niphr.github.io/csalert/articles/pipeline.html), which runs one
series through every stage.
