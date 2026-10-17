# The v4 tasks for norsyss.cs9

These are the specs of the 4 v4 tasks that norsyss.cs9 wires: the nowcast, the short-term trend, HLM and MEM. The norsyss.cs9 session owns the wiring. csalert supplies the functions and these specs. `data-raw/v4_norsyss_validation.R` checks every spec against the real v4 output on the national series of `norsyss_respiratory_v1_2026-10-13.csv`.

## Rules for every task

- The nowcast is a passthrough. Task 1 stores it in the compressed form, one point value and 9 percentiles per base measure. Tasks 2 to 4 read that table.
- `as_ensemble_v4()` needs a data.table. A table that DBI reads MUST go through `data.table::setDT()` before `as_ensemble_v4()`.
- Read the nowcast table with `n_sim = 1`. Every percentile of a passthrough is `NULL`, so each rebuilt draw equals the point value. A larger `n_sim` costs time, and the trend then takes its growth-rate percentiles from simulated t draws in place of the closed form. Change `n_sim` when a real nowcast replaces the passthrough.
- The identity columns of a series are `granularity_geo`, `location_code`, `age`, `sex`, `tariffgroup_tag` and `icpc2grp_tag`. Pass them as `id_cols`. With `isoyearweek` they form the unique key of every table.
- The key columns are `TEXT NOT NULL`. Every other column allows `NULL`, because a quantile, a probability or a threshold is `NULL` where the method gives no value.
- The types follow the output: `DOUBLE PRECISION` for a point, quantile, probability or threshold, and `INTEGER` for a season count. In the cs9 `field_types`, write `DOUBLE`, which csdb creates as `DOUBLE PRECISION`.
- Each name is at most 63 UTF-8 bytes, the PostgreSQL limit. The validation script checks every table, column and partition name in this file.
- The tables hold few of the csfmt_rts_data_v2 columns. Use `csdb::validator_field_types_blank` and `csdb::validator_field_contents_blank`.
- Each task empties its table on the first plan and writes every week. The compressed table has no mode that writes only changed weeks.

## The plans

Tasks 1 to 3 have one plan per ICPC-2 group, and each plan writes one partition. The partition column is `icpc2grp_tag`, and cs9 names a partition `<table>_xxpxx_<tag>`. The longest is `anon_lss_short_term_trends_v4_xxpxx_respiratory_infections`, at 58 bytes. A plan holds the 189 series of the current trend and HLM tasks. They are 21 locations (1 nation, 5 georegions and 15 counties at border 2024) by 9 ages, with `sex = "total"`.

Task 4 has one plan, the `r80` partition of the nowcast table, and writes one table.

The expected rows per plan:

| Task | Table | Rows per plan | For 2006-01 to 2026-41 |
|---|---|---|---|
| 1. nowcast | `anon_lss_nowcast_v4` | one row per series and week, from the first week of the series to its last | 1,084 per series; at most 204,876 |
| 2. trend | `anon_lss_short_term_trends_v4` | the rows of task 1 | the same |
| 3. HLM | `anon_lss_signals_v4` | the rows of task 1 | the same |
| 4. MEM | `anon_r80_mem_v4` | the `r80` rows of task 1 in ISO weeks 1 to 20 and 40 to 52 | 682 per series; at most 128,898 |

The counts per series are measured on the national series of the csv. The maxima assume that all 189 series hold every week.

## Task 1: the nowcast

The task builds the reporting triangle from the weekly counts. Each week has one report, on the Sunday that ends it. Rename the counts to `numerator` and `denominator`. The numerator is `consultations_icpc2group_n`. The denominator is `consultations_all_n` for a group where `includes_influenza_covid19` is `TRUE`, and `consultations_without_influenza_covid19_n` for every other group, as in the current tasks.

```r
tri <- csfmt_reporting_triangle_v4(d, id_cols = id_cols, value_col = "numerator")
ens <- nowcast_passthrough_v4(tri, max_delay_days = 7, denominator_col = "denominator")
ens <- ens_add_rate_v4(ens, numerator = "numerator", denominator = "denominator", per = 100, name = "numerator_vs_denominator_pr100")
out <- ens_compress_v4(ens)
out[, c("time_series_id", "time_series_label", "time_series_internal_id") := NULL]
```

Drop the 3 `time_series_*` columns before the insert. `as_ensemble_v4()` builds them again. The column `original` is the observed numerator, and `denominator_observed` the observed denominator.

```sql
CREATE TABLE anon_lss_nowcast_v4 (
  granularity_geo TEXT NOT NULL,
  location_code TEXT NOT NULL,
  age TEXT NOT NULL,
  sex TEXT NOT NULL,
  tariffgroup_tag TEXT NOT NULL,
  isoyearweek TEXT NOT NULL,
  original DOUBLE PRECISION,
  denominator_observed DOUBLE PRECISION,
  numerator DOUBLE PRECISION,
  numerator_q02x5 DOUBLE PRECISION,
  numerator_q05x0 DOUBLE PRECISION,
  numerator_q10x0 DOUBLE PRECISION,
  numerator_q25x0 DOUBLE PRECISION,
  numerator_q50x0 DOUBLE PRECISION,
  numerator_q75x0 DOUBLE PRECISION,
  numerator_q90x0 DOUBLE PRECISION,
  numerator_q95x0 DOUBLE PRECISION,
  numerator_q97x5 DOUBLE PRECISION,
  denominator DOUBLE PRECISION,
  denominator_q02x5 DOUBLE PRECISION,
  denominator_q05x0 DOUBLE PRECISION,
  denominator_q10x0 DOUBLE PRECISION,
  denominator_q25x0 DOUBLE PRECISION,
  denominator_q50x0 DOUBLE PRECISION,
  denominator_q75x0 DOUBLE PRECISION,
  denominator_q90x0 DOUBLE PRECISION,
  denominator_q95x0 DOUBLE PRECISION,
  denominator_q97x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q02x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q05x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q10x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q25x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q50x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q75x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q90x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q95x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_q97x5 DOUBLE PRECISION,
  icpc2grp_tag TEXT NOT NULL,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek, icpc2grp_tag)
);
```

## Task 2: the short-term trend

The trend fits the count with the denominator as the offset, so it models the rate. The window is 5 weeks, as in the current task. A week is increasing when `numerator_vs_denominator_pr100_trend_pinc >= 0.95`, which is `1 - alpha / 2` with the current `alpha = 0.10`.

```r
x <- as_ensemble_v4(data.table::setDT(d), id_cols = id_cols, n_sim = 1)
x <- short_term_trend_v4(x, measure = "numerator", width = 5, denominator = "denominator", name = "numerator_vs_denominator_pr100", seed = 4)
out <- x$data[, c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

Here `new_cols` are the 11 columns that the step adds, as below. The first 4 weeks of a series have no window, and their values are `NULL`.

```sql
CREATE TABLE anon_lss_short_term_trends_v4 (
  granularity_geo TEXT NOT NULL,
  location_code TEXT NOT NULL,
  age TEXT NOT NULL,
  sex TEXT NOT NULL,
  tariffgroup_tag TEXT NOT NULL,
  isoyearweek TEXT NOT NULL,
  numerator_vs_denominator_pr100_trend_pinc DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q02x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q05x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q10x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q25x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q50x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q75x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q90x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q95x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q97x5 DOUBLE PRECISION,
  icpc2grp_tag TEXT NOT NULL,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek, icpc2grp_tag)
);
```

## Task 3: HLM

HLM compares the rate with the limit of a 5-year baseline, as in the current task. Add the rate again from its parts before the step, as `as_ensemble_v4()` says. A week is high when `numerator_vs_denominator_pr100_hlm_prob_high` is 1. v4 flags a value at the limit as high, where v1 flags only a value above it.

```r
x <- as_ensemble_v4(data.table::setDT(d), id_cols = id_cols, n_sim = 1)
x <- ens_add_rate_v4(x, numerator = "numerator", denominator = "denominator", per = 100, name = "numerator_vs_denominator_pr100")
x <- signal_detection_hlm_v4(x, measure = "numerator_vs_denominator_pr100", baseline_isoyears = 5)
out <- x$data[, c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

```sql
CREATE TABLE anon_lss_signals_v4 (
  granularity_geo TEXT NOT NULL,
  location_code TEXT NOT NULL,
  age TEXT NOT NULL,
  sex TEXT NOT NULL,
  tariffgroup_tag TEXT NOT NULL,
  isoyearweek TEXT NOT NULL,
  numerator_vs_denominator_pr100_hlm_thr DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_prob_null DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_prob_high DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q02x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q05x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q10x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q25x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q50x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q75x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q90x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q95x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_q97x5 DOUBLE PRECISION,
  icpc2grp_tag TEXT NOT NULL,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek, icpc2grp_tag)
);
```

## Task 4: MEM

MEM reads the `r80` partition of the nowcast table in ISO weeks 1 to 20 and 40 to 52, the weeks of `r80_estimate_mem_thresholds`. Filter the rows before `as_ensemble_v4()`. On all weeks of the national series, the v4 pre-epidemic threshold differs from the v1 fit by up to 16%. The other arguments are those of `r80_estimate_mem_thresholds`: `i.seasons = 10` and the 4 excluded seasons.

```r
d <- data.table::setDT(d)[as.integer(substr(isoyearweek, 6, 7)) %in% c(1:20, 40:52)]
x <- as_ensemble_v4(d, id_cols = id_cols, n_sim = 1)
x <- ens_add_rate_v4(x, numerator = "numerator", denominator = "denominator", per = 100, name = "numerator_vs_denominator_pr100")
x <- mem_thresholds_v4(x, measure = "numerator_vs_denominator_pr100", min_seasons = 2, i.seasons = 10, exclude_seasons = c("2009/2010", "2019/2020", "2020/2021", "2021/2022"))
out <- x$data[, c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

On the national series, each of the 4 thresholds is within 0.02% of the v1 fit in each of the 17 seasons that both fit. The v1 rate is rounded to 3 decimals, and the v4 rate is not. v4 also fits 2008/2009 and 2009/2010, which norsyss.cs9 leaves out as the first 5 seasons of the data.

The task covers the share of all consultations on the 189 series. It does not cover the per-100,000 rate of the `tessy` type, or the `r80` age groups 015_064 and 065p.

```sql
CREATE TABLE anon_r80_mem_v4 (
  granularity_geo TEXT NOT NULL,
  location_code TEXT NOT NULL,
  age TEXT NOT NULL,
  sex TEXT NOT NULL,
  tariffgroup_tag TEXT NOT NULL,
  isoyearweek TEXT NOT NULL,
  numerator_vs_denominator_pr100_mem_thr_preepidemic DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_medium DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_high DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_veryhigh DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_n_seasons INTEGER,
  numerator_vs_denominator_pr100_mem_prob_preepidemic DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_low DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_medium DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_high DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_veryhigh DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q02x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q05x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q10x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q25x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q50x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q75x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q90x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q95x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_q97x5 DOUBLE PRECISION,
  icpc2grp_tag TEXT NOT NULL,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek, icpc2grp_tag)
);
```
