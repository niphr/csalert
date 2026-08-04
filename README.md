# csalert <a href="https://niphr.github.io/csalert/"><img src="man/figures/logo.png" align="right" width="120" /></a>

[![CRAN status](https://www.r-pkg.org/badges/version/csalert)](https://cran.r-project.org/package=csalert)
[![CRAN downloads](https://cranlogs.r-pkg.org/badges/csalert)](https://cran.r-project.org/package=csalert)

## Overview 

[csalert](https://niphr.github.io/csalert/) helps create alerts from public health surveillance data.

There are two ways in, and they are separate implementations.

**Direct methods** run on a weekly `cstidy` table and add fitted columns and prediction
intervals to it. `short_term_trend()` classifies the recent trend with the quasi-Poisson
analytics strategy of Benedetti (2019),
[doi:10.5588/pha.19.0002](https://doi.org/10.5588/pha.19.0002);
`signal_detection_hlm()` flags counts above a modelled historical baseline. The quick
start below uses this route.

**The ensemble route** starts a step earlier, from a reporting triangle that records when
each count arrived. A nowcast engine completes the weeks that are not fully reported into
Monte-Carlo draws; rate, trend, MEM intensity and exceedance stages then run per draw; and
`ens_collapse()` reduces the draws to quantiles at the end. Use it when the delay itself
matters. Note the trend on this route is a rolling OLS slope over draws, not the
Benedetti method. See
[the nowcasting article](https://niphr.github.io/csalert/articles/nowcasting.html).

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

d <- cstidy::nor_covid19_icu_and_hospitalization_csfmt_rts_v1[granularity_time == "isoyearweek"]

res <- short_term_trend(d, numerator = "hospitalization_with_covid19_as_primary_cause_n")

res[, .(isoyearweek, hospitalization_with_covid19_as_primary_cause_trend0_41_status)]
```

## Which function do I want?

| Goal | Function |
| --- | --- |
| Label recent weeks increasing or not increasing (add `include_decreasing = TRUE` for a decreasing level) | `short_term_trend()` |
| Flag counts that exceed a modelled historical baseline | `signal_detection_hlm()` |
| Fill in weeks that are not fully reported yet | `nowcast_quasipoisson_v1()` |
| Send an indicator through unchanged, without filling in | `nowcast_passthrough_to_ensemble_v1()` |
| Measure a nowcast's interval coverage and revision on replayed weeks | `nowcast_evaluate_v1()` |
| Measure how quickly cases arrive, within a chosen delay horizon | `reporting_completion_v1()` |
| Classify weekly intensity against season-specific MEM thresholds | `mem_thresholds_v1()` |
| Turn Monte-Carlo draws into quantile columns | `ens_collapse()` |
| Check that a feed has rows, has its reference column, and is not stale | `qc_surveillance_data_v1()` |
| Diff every value column of this run against the previous run | `compare_results()` |
| Split that diff into settled-week changes and frontier status moves | `qc_week_over_week_v1()` |
| Make synthetic data to test a method on | `simulate_baseline_data()` |

## Documentation

Full documentation is at <https://niphr.github.io/csalert/>: the
[function reference](https://niphr.github.io/csalert/reference/index.html), and two
articles, [Short term trend](https://niphr.github.io/csalert/articles/short_term_trend.html)
and [Nowcasting](https://niphr.github.io/csalert/articles/nowcasting.html).
