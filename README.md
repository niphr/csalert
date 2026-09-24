# csalert <a href="https://niphr.github.io/csalert/"><img src="man/figures/logo.png" align="right" width="120" /></a>

[![CRAN status](https://www.r-pkg.org/badges/version/csalert)](https://cran.r-project.org/package=csalert)
[![CRAN downloads](https://cranlogs.r-pkg.org/badges/csalert)](https://cran.r-project.org/package=csalert)

## Overview

[csalert](https://niphr.github.io/csalert/) makes alerts from weekly
public-health surveillance counts that arrive late.

It starts from a **reporting triangle**: the counts, and the date each count was
reported. A nowcast engine completes the weeks still being reported, as
Monte-Carlo draws. Rate, trend, MEM intensity and baseline exceedance run on
those draws, so the reporting uncertainty reaches the alert.

The table methods of `short_term_trend()` and `signal_detection_hlm()`, after
Benedetti (2019),
[doi:10.5588/pha.19.0002](https://doi.org/10.5588/pha.19.0002), are
**deprecated**. They still work with no warning, but they take different
arguments and give different numbers.

## Installation

Install from the niphr r-universe, which builds every commit on `main`:

``` r
options(repos = c(
  niphr = "https://niphr.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))
install.packages("csalert")
```

Put those `repos` in your `~/.Rprofile`. Without them, R installs 2024.6.24
from CRAN, **years behind**, and nothing warns you.

With the repos set, `pak` works too:

``` r
pak::pak("csalert")            # the r-universe build
pak::pak("niphr/csalert")      # straight from GitHub, ignores the repo list
```

`pak` rejects a version range such as `csalert@>=2026.8.27`. Pin an exact
version, `csalert@2026.8.27`, or declare `Imports: csalert (>= 2026.8.27)` in a
`DESCRIPTION` and run `pak::local_install_deps()`.

## Quick start

``` r
library(csalert)
library(data.table)

# counts, and the date each count was reported on
mondays <- as.Date("2023-01-02") + 7 * (0:51)
monday <- rep(mondays, each = 3)
d <- data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 52),
  numerator = rpois(156, c(40, 20, 8)),
  indicator_tag = "hospitalisation", location_code = "nation",
  age = "total", sex = "total"
)
d <- d[reporting_date <= mondays[52] + 6]

tri <- csfmt_reporting_triangle_v3(
  d, id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# complete the weeks still arriving, then the trend on the draws
ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 21, n_sim = 500)
ens <- short_term_trend(ens, measure = "numerator_nowcasted", trend_isoyearweeks = 5)

# one tidy table at the end
res <- ens_collapse(ens, heal = TRUE)
res[, .(isoyearweek, numerator_nowcasted_q50x0,
        numerator_nowcasted_trend_increasing_pr)]
```

## Which function do I want?

| Goal | Function |
| --- | --- |
| Build the input triangle | `csfmt_reporting_triangle_v3()` |
| Complete the weeks still being reported | `nowcast_delay_ecdf_v1()` |
| Pass an indicator through with no nowcast | `nowcast_passthrough_to_ensemble_v1()` |
| Score a nowcast on replayed weeks | `nowcast_evaluate_v1()` |
| Measure how fast cases arrive | `reporting_completion_v1()` |
| Add a rate | `ens_add_rate()` |
| Estimate recent direction, per draw | `short_term_trend()` |
| Classify intensity by MEM thresholds | `mem_thresholds_v1()` |
| Flag counts above a historical baseline | `signal_detection_hlm()` |
| Turn the draws into quantile columns | `ens_collapse()` |
| Check an input feed | `qc_surveillance_data_v1()` |
| Compare this run with the previous run | `qc_week_over_week_v1()`, `compare_results()` |
| Simulate counts with known outbreaks | `simulate_baseline_data()` |

`short_term_trend()` and `signal_detection_hlm()` run the current method on a
`csfmt_ensemble_v3`, and the deprecated method on a `csfmt_rts_data_v1`.

## Documentation

Read <https://niphr.github.io/csalert/>. Start with
[Get started](https://niphr.github.io/csalert/articles/csalert.html), then
[The pipeline](https://niphr.github.io/csalert/articles/pipeline.html), which
runs one series through every stage.
