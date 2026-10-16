# Changed cells of the v1 reference fixture in 2026.10.17

`v1_reference.rds` stores the output of the v1 method of csalert 94100f5. In 2026.10.17 the v1 method runs on `.v4_rolling_qp_offset()` and calls no `glm2`. The cells below changed for that reason. Every other cell is identical to the Phase 1 fixture, git blob `460bc02`.

A cell is changed when a rerun differs from the Phase 1 output under the rules of `test-v1_reference.R`. Status and forecast cells are compared exactly. Doubling days are compared within a relative tolerance of 1e-6.

The rules:

The rows with an NA count or denominator leave the fit. The first of rules 3, 2 and 4 that holds for a window decides its status and doubling days:

- **Rule 3.** A window with NA rows and fewer than 3 rows left gets NA status and NA doubling days.
- **Rule 2.** A window where every count left is 0 gets `notincreasing`, or `null` with `include_decreasing`, and NA doubling days. Without NA rows, this rule holds at every width, also at width 2.
- **Rule 4.** A window gets NA status and doubling days when its fit does not converge, has a non-finite value, or has separated counts. The counts are separated when every count above 0 sits at the first or the last row of the fit. The kernel fits no window of fewer than 3 rows, so a width-2 window with a count above 0 also gets NA here.
- **Rule 5.** A window where `glm2` halves the step, but the kernel converges, gets the kernel's estimate.
- **Rule 6.** The forecast comes from the kernel's fit of the last window. It is NA when that fit falls under rule 3 or rule 4.

Rows are rows of the stored output, after `remove_training_data`. In every case below, the output has one series.

## Changed cells per case and rule: 830 cells

| case | rule 2 | rule 3 | rule 4 | rule 6 | total |
|---|---|---|---|---|---|
| allzero_den | 5 | 0 | 4 | 0 | 9 |
| allzero_noden | 5 | 0 | 4 | 0 | 9 |
| few_nonna_den | 0 | 2 | 0 | 0 | 2 |
| few_nonna_noden | 0 | 4 | 0 | 0 | 4 |
| last_window_na_den | 0 | 2 | 0 | 0 | 2 |
| real_covid19 | 735 | 0 | 2 | 0 | 737 |
| separated_den | 0 | 0 | 8 | 0 | 8 |
| separated_noden | 0 | 0 | 8 | 0 | 8 |
| width2_den | 0 | 0 | 6 | 33 | 39 |
| width2_noden | 0 | 0 | 6 | 6 | 12 |

No cell changed under rule 5. In the 3,902 windows of these cases, `glm2` warns in 4 windows, and none of them has a count left. It halves the step in none.

## The case whose stored outcome changed

`last_window_na_noden`: on 94100f5, v1 stopped with "object 'varname_forecast_denominator' not found". The last window has no count, so rule 6 gives NA forecasts, as `last_window_na_den` has. Its stored outcome is now an output of 18 rows and 24 columns. Its input columns are the input. Its computed columns are:

| isoyearweek | numerator_forecasted_n | numerator_forecasted_predinterval_q02x5_n | numerator_forecasted_predinterval_q97x5_n | numerator_forecasted_n_forecast | numerator_trend0_34_status | numerator_doublingdays0_34 |
|---|---|---|---|---|---|---|
| 2020-05 | 14 | NA | NA | FALSE | notincreasing | 66.9 |
| 2020-06 | 27 | NA | NA | FALSE | notincreasing | 40.3 |
| 2020-07 | 29 | NA | NA | FALSE | notincreasing | 34.3 |
| 2020-08 | 35 | NA | NA | FALSE | increasing | 25.2 |
| 2020-09 | 42 | NA | NA | FALSE | increasing | 21.8 |
| 2020-10 | 43 | NA | NA | FALSE | increasing | 37.7 |
| 2020-11 | 59 | NA | NA | FALSE | increasing | 29.3 |
| 2020-12 | 58 | NA | NA | FALSE | increasing | 36.2 |
| 2020-13 | 68 | NA | NA | FALSE | increasing | 38.8 |
| 2020-14 | 87 | NA | NA | FALSE | increasing | 31.2 |
| 2020-15 | 74 | NA | NA | FALSE | notincreasing | 56.7 |
| 2020-16 | NA | NA | NA | FALSE | notincreasing | 51.8 |
| 2020-17 | NA | NA | NA | FALSE | notincreasing | 123.4 |
| 2020-18 | NA | NA | NA | FALSE | NA | NA |
| 2020-19 | NA | NA | NA | FALSE | NA | NA |
| 2020-20 | NA | NA | NA | FALSE | NA | NA |
| 2020-21 | NA | NA | NA | TRUE | forecast | NA |
| 2020-22 | NA | NA | NA | TRUE | forecast | NA |

## The cases added in round 2

`width2_allzero_den` and `width2_allzero_noden` are new. Their input is the input of `allzero_den`, with the numerator of week 2020-12 set to NA. The counts of weeks 2020-06 to 2020-14 are 0. The window is 2 weeks wide. The stored output is that of the 2026.10.17 code. The status and doubling days of each week, with the rule that gives them, are:

| case | week | numerator | status | doubling_days | rule | why |
|---|---|---|---|---|---|---|
| width2_allzero_den | 2020-02 | 18 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-03 | 26 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-04 | 16 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-05 | 23 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-06 | 0 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-07 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-08 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-09 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-10 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-11 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-12 | NA | NA | NA | 3 | NA rows, 1 row left |
| width2_allzero_den | 2020-13 | 0 | NA | NA | 3 | NA rows, 1 row left |
| width2_allzero_den | 2020-14 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_den | 2020-15 | 26 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-16 | 17 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-17 | 21 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-18 | 25 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-19 | 13 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-20 | 23 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_den | 2020-21 | NA | forecast | NA |  |  |
| width2_allzero_den | 2020-22 | NA | forecast | NA |  |  |
| width2_allzero_noden | 2020-02 | 18 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-03 | 26 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-04 | 16 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-05 | 23 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-06 | 0 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-07 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-08 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-09 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-10 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-11 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-12 | NA | NA | NA | 3 | NA rows, 1 row left |
| width2_allzero_noden | 2020-13 | 0 | NA | NA | 3 | NA rows, 1 row left |
| width2_allzero_noden | 2020-14 | 0 | notincreasing | NA | 2 | every count is 0 |
| width2_allzero_noden | 2020-15 | 26 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-16 | 17 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-17 | 21 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-18 | 25 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-19 | 13 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-20 | 23 | NA | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_allzero_noden | 2020-21 | NA | forecast | NA |  |  |
| width2_allzero_noden | 2020-22 | NA | forecast | NA |  |  |

## Every changed cell

| case | column | row | week | old | new | rule | why |
|---|---|---|---|---|---|---|---|
| allzero_den | numerator_vs_denominator_trend0_34_status | 5 | 2020-09 | notincreasing | NA | 4 | separated |
| allzero_den | numerator_vs_denominator_trend0_34_status | 11 | 2020-15 | increasing | NA | 4 | separated |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 5 | 2020-09 | -0.2 | NA | 4 | separated |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 6 | 2020-10 | -290.5 | NA | 2 | every count is 0 |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 7 | 2020-11 | 997.7 | NA | 2 | every count is 0 |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 8 | 2020-12 | 829.3 | NA | 2 | every count is 0 |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 9 | 2020-13 | 6106.2 | NA | 2 | every count is 0 |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 10 | 2020-14 | -6910.1 | NA | 2 | every count is 0 |
| allzero_den | numerator_vs_denominator_doublingdays0_34 | 11 | 2020-15 | 0.2 | NA | 4 | separated |
| allzero_noden | numerator_trend0_34_status | 5 | 2020-09 | notincreasing | NA | 4 | separated |
| allzero_noden | numerator_trend0_34_status | 11 | 2020-15 | increasing | NA | 4 | separated |
| allzero_noden | numerator_doublingdays0_34 | 5 | 2020-09 | -0.2 | NA | 4 | separated |
| allzero_noden | numerator_doublingdays0_34 | 6 | 2020-10 | -598732575809836 | NA | 2 | every count is 0 |
| allzero_noden | numerator_doublingdays0_34 | 7 | 2020-11 | 912083875243561 | NA | 2 | every count is 0 |
| allzero_noden | numerator_doublingdays0_34 | 8 | 2020-12 | 1161836207404818 | NA | 2 | every count is 0 |
| allzero_noden | numerator_doublingdays0_34 | 9 | 2020-13 | -1314959874248307 | NA | 2 | every count is 0 |
| allzero_noden | numerator_doublingdays0_34 | 10 | 2020-14 | -1436108531072894 | NA | 2 | every count is 0 |
| allzero_noden | numerator_doublingdays0_34 | 11 | 2020-15 | 0.2 | NA | 4 | separated |
| separated_den | numerator_vs_denominator_trend0_34_status | 3 | 2020-07 | notincreasing | NA | 4 | separated |
| separated_den | numerator_vs_denominator_trend0_34_status | 4 | 2020-08 | increasing | NA | 4 | separated |
| separated_den | numerator_vs_denominator_trend0_34_status | 11 | 2020-15 | notincreasing | NA | 4 | separated |
| separated_den | numerator_vs_denominator_trend0_34_status | 12 | 2020-16 | increasing | NA | 4 | separated |
| separated_den | numerator_vs_denominator_doublingdays0_34 | 3 | 2020-07 | -0.2 | NA | 4 | separated |
| separated_den | numerator_vs_denominator_doublingdays0_34 | 4 | 2020-08 | 0.2 | NA | 4 | separated |
| separated_den | numerator_vs_denominator_doublingdays0_34 | 11 | 2020-15 | -0.2 | NA | 4 | separated |
| separated_den | numerator_vs_denominator_doublingdays0_34 | 12 | 2020-16 | 0.2 | NA | 4 | separated |
| separated_noden | numerator_trend0_34_status | 3 | 2020-07 | notincreasing | NA | 4 | separated |
| separated_noden | numerator_trend0_34_status | 4 | 2020-08 | increasing | NA | 4 | separated |
| separated_noden | numerator_trend0_34_status | 11 | 2020-15 | notincreasing | NA | 4 | separated |
| separated_noden | numerator_trend0_34_status | 12 | 2020-16 | increasing | NA | 4 | separated |
| separated_noden | numerator_doublingdays0_34 | 3 | 2020-07 | -0.2 | NA | 4 | separated |
| separated_noden | numerator_doublingdays0_34 | 4 | 2020-08 | 0.2 | NA | 4 | separated |
| separated_noden | numerator_doublingdays0_34 | 11 | 2020-15 | -0.2 | NA | 4 | separated |
| separated_noden | numerator_doublingdays0_34 | 12 | 2020-16 | 0.2 | NA | 4 | separated |
| few_nonna_den | numerator_vs_denominator_trend0_34_status | 10 | 2020-14 | notincreasing | NA | 3 | NA rows, 2 rows left |
| few_nonna_den | numerator_vs_denominator_doublingdays0_34 | 10 | 2020-14 | -16.6 | NA | 3 | NA rows, 2 rows left |
| few_nonna_noden | numerator_trend0_34_status | 6 | 2020-10 | notincreasing | NA | 3 | NA rows, 2 rows left |
| few_nonna_noden | numerator_trend0_34_status | 10 | 2020-14 | notincreasing | NA | 3 | NA rows, 2 rows left |
| few_nonna_noden | numerator_doublingdays0_34 | 6 | 2020-10 | Inf | NA | 3 | NA rows, 2 rows left |
| few_nonna_noden | numerator_doublingdays0_34 | 10 | 2020-14 | -13.9 | NA | 3 | NA rows, 2 rows left |
| last_window_na_den | numerator_vs_denominator_trend0_34_status | 14 | 2020-18 | notincreasing | NA | 3 | NA rows, 2 rows left |
| last_window_na_den | numerator_vs_denominator_doublingdays0_34 | 14 | 2020-18 | -44.8 | NA | 3 | NA rows, 2 rows left |
| width2_den | numerator_forecasted_n | 20 | 2020-21 | 230 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_forecasted_n | 21 | 2020-22 | 243 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | denominator_forecasted_n | 20 | 2020-21 | 2030 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | denominator_forecasted_n | 21 | 2020-22 | 2089 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_forecasted_predinterval_q02x5_n | 20 | 2020-21 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_forecasted_predinterval_q02x5_n | 21 | 2020-22 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_forecasted_predinterval_q97x5_n | 20 | 2020-21 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_forecasted_predinterval_q97x5_n | 21 | 2020-22 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 1 | 2020-02 | 0.719794344473008 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 2 | 2020-03 | 0.39177277179236 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 3 | 2020-04 | 0.584510472479299 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 4 | 2020-05 | 0.92277804759592 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 5 | 2020-06 | 1.22970978848992 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 6 | 2020-07 | 1.70854271356784 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 7 | 2020-08 | 1.48221343873518 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 8 | 2020-09 | 1.83673469387755 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 9 | 2020-10 | 2.04678362573099 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 10 | 2020-11 | 2.40615976900866 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 11 | 2020-12 | 2.58992805755396 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 12 | 2020-13 | 2.97741273100616 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 13 | 2020-14 | 4.72320975114271 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 14 | 2020-15 | 5.58092338914257 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 15 | 2020-16 | 5.26315789473684 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 16 | 2020-17 | 7.2528564331843 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 17 | 2020-18 | 7.65743073047859 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 18 | 2020-19 | 10.6993736951983 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 19 | 2020-20 | 11.0040567951318 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 20 | 2020-21 | 11.3300492610837 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_pr100 | 21 | 2020-22 | 11.6323599808521 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_predinterval_q02x5_pr100 | 20 | 2020-21 | 0 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_predinterval_q02x5_pr100 | 21 | 2020-22 | 0 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_predinterval_q97x5_pr100 | 20 | 2020-21 | 0 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_forecasted_predinterval_q97x5_pr100 | 21 | 2020-22 | 0 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_den | numerator_vs_denominator_trend0_13_status | 2 | 2020-03 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_den | numerator_vs_denominator_trend0_13_status | 7 | 2020-08 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_den | numerator_vs_denominator_trend0_13_status | 15 | 2020-16 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_den | numerator_vs_denominator_doublingdays0_13 | 2 | 2020-03 | -8 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_den | numerator_vs_denominator_doublingdays0_13 | 7 | 2020-08 | -34.1 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_den | numerator_vs_denominator_doublingdays0_13 | 15 | 2020-16 | -82.8 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_forecasted_n | 20 | 2020-21 | 230 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_forecasted_n | 21 | 2020-22 | 243 | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_forecasted_predinterval_q02x5_n | 20 | 2020-21 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_forecasted_predinterval_q02x5_n | 21 | 2020-22 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_forecasted_predinterval_q97x5_n | 20 | 2020-21 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_forecasted_predinterval_q97x5_n | 21 | 2020-22 | NaN | NA | 6 | last window: 2 rows, no NA: the kernel fits no window of fewer than 3 rows (rule 4) |
| width2_noden | numerator_trend0_13_status | 2 | 2020-03 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_trend0_13_status | 7 | 2020-08 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_trend0_13_status | 15 | 2020-16 | notincreasing | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_doublingdays0_13 | 2 | 2020-03 | -8.7 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_doublingdays0_13 | 7 | 2020-08 | -38.8 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| width2_noden | numerator_doublingdays0_13 | 15 | 2020-16 | -86.5 | NA | 4 | 2 rows, no NA: the kernel fits no window of fewer than 3 rows |
| real_covid19 | numerator_vs_denominator_trend0_34_status | 736 | 2020-10 | increasing | NA | 4 | separated |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 1 | 2006-05 | -826 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 2 | 2006-06 | -1019.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 3 | 2006-07 | -958.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 4 | 2006-08 | 345.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 5 | 2006-09 | 205.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 6 | 2006-10 | 448.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 7 | 2006-11 | -1084.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 8 | 2006-12 | -200.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 9 | 2006-13 | -256.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 10 | 2006-14 | -253.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 11 | 2006-15 | 31.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 12 | 2006-16 | 45.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 13 | 2006-17 | 437.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 14 | 2006-18 | -121.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 15 | 2006-19 | -29.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 16 | 2006-20 | 2420.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 17 | 2006-21 | 139.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 18 | 2006-22 | -239.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 19 | 2006-23 | 196.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 20 | 2006-24 | -167.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 21 | 2006-25 | -165.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 22 | 2006-26 | 354.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 23 | 2006-27 | 154.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 24 | 2006-28 | 48.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 25 | 2006-29 | 41.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 26 | 2006-30 | 53.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 27 | 2006-31 | 138.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 28 | 2006-32 | -169.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 29 | 2006-33 | -51 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 30 | 2006-34 | -40 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 31 | 2006-35 | -49.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 32 | 2006-36 | -73.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 33 | 2006-37 | -175.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 34 | 2006-38 | -383.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 35 | 2006-39 | -396.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 36 | 2006-40 | 469.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 37 | 2006-41 | 409 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 38 | 2006-42 | -3251.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 39 | 2006-43 | -24795.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 40 | 2006-44 | -269 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 41 | 2006-45 | -447.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 42 | 2006-46 | -615.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 43 | 2006-47 | -411.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 44 | 2006-48 | -3828.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 45 | 2006-49 | -666.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 46 | 2006-50 | -362.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 47 | 2006-51 | -573.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 48 | 2006-52 | 25.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 49 | 2007-01 | 32.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 50 | 2007-02 | 110 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 51 | 2007-03 | -62.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 52 | 2007-04 | -25.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 53 | 2007-05 | -124.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 54 | 2007-06 | -1039.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 55 | 2007-07 | -443.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 56 | 2007-08 | 500.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 57 | 2007-09 | 335.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 58 | 2007-10 | 1164.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 59 | 2007-11 | -908.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 60 | 2007-12 | -348.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 61 | 2007-13 | -598.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 62 | 2007-14 | 28.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 63 | 2007-15 | 42.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 64 | 2007-16 | 466.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 65 | 2007-17 | -61.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 66 | 2007-18 | -30.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 67 | 2007-19 | -507.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 68 | 2007-20 | 110.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 69 | 2007-21 | -3666.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 70 | 2007-22 | 1109.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 71 | 2007-23 | -2824 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 72 | 2007-24 | -130.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 73 | 2007-25 | -319.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 74 | 2007-26 | -297 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 75 | 2007-27 | 72.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 76 | 2007-28 | 46.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 77 | 2007-29 | 40.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 78 | 2007-30 | 53.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 79 | 2007-31 | 147.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 80 | 2007-32 | -195.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 81 | 2007-33 | -54.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 82 | 2007-34 | -40.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 83 | 2007-35 | -46.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 84 | 2007-36 | -68.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 85 | 2007-37 | -175.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 86 | 2007-38 | -911.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 87 | 2007-39 | -2339.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 88 | 2007-40 | 395.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 89 | 2007-41 | 501.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 90 | 2007-42 | -1209.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 91 | 2007-43 | -747.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 92 | 2007-44 | -195.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 93 | 2007-45 | -346.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 94 | 2007-46 | -595.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 95 | 2007-47 | -406.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 96 | 2007-48 | -2022.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 97 | 2007-49 | -339.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 98 | 2007-50 | -286.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 99 | 2007-51 | -268.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 100 | 2007-52 | 23.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 101 | 2008-01 | 24.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 102 | 2008-02 | 83.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 103 | 2008-03 | -55.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 104 | 2008-04 | -20.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 105 | 2008-05 | -67.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 106 | 2008-06 | 536.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 107 | 2008-07 | 1005.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 108 | 2008-08 | 194 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 109 | 2008-09 | 723.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 110 | 2008-10 | -2482.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 111 | 2008-11 | -172 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 112 | 2008-12 | 37.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 113 | 2008-13 | 44.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 114 | 2008-14 | 621.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 115 | 2008-15 | -71.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 116 | 2008-16 | -27.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 117 | 2008-17 | -183.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 118 | 2008-18 | 122.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 119 | 2008-19 | 391.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 120 | 2008-20 | 144.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 121 | 2008-21 | 2530.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 122 | 2008-22 | -163.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 123 | 2008-23 | -423.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 124 | 2008-24 | -137.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 125 | 2008-25 | -16514.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 126 | 2008-26 | 217.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 127 | 2008-27 | 87.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 128 | 2008-28 | 53.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 129 | 2008-29 | 44.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 130 | 2008-30 | 50.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 131 | 2008-31 | 86.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 132 | 2008-32 | -1087.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 133 | 2008-33 | -74.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 134 | 2008-34 | -43.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 135 | 2008-35 | -43.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 136 | 2008-36 | -58.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 137 | 2008-37 | -114.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 138 | 2008-38 | -359.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 139 | 2008-39 | -667.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 140 | 2008-40 | 723.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 141 | 2008-41 | 418.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 142 | 2008-42 | 7421.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 143 | 2008-43 | -341.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 144 | 2008-44 | -465.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 145 | 2008-45 | -697.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 146 | 2008-46 | -2813.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 147 | 2008-47 | -1015 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 148 | 2008-48 | -276.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 149 | 2008-49 | -564.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 150 | 2008-50 | -324.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 151 | 2008-51 | -179.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 152 | 2008-52 | 35.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 153 | 2009-01 | 21.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 154 | 2009-02 | 57.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 155 | 2009-03 | -86.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 156 | 2009-04 | -22.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 157 | 2009-05 | -35.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 158 | 2009-06 | 282.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 159 | 2009-07 | 376.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 160 | 2009-08 | 203 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 161 | 2009-09 | 349.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 162 | 2009-10 | 1037.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 163 | 2009-11 | -746.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 164 | 2009-12 | -259 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 165 | 2009-13 | -540.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 166 | 2009-14 | -273.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 167 | 2009-15 | 30.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 168 | 2009-16 | 43.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 169 | 2009-17 | 264 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 170 | 2009-18 | -87.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 171 | 2009-19 | -27.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 172 | 2009-20 | -166.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 173 | 2009-21 | 189.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 174 | 2009-22 | -715.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 175 | 2009-23 | 137.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 176 | 2009-24 | 1236.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 177 | 2009-25 | -141.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 178 | 2009-26 | 2671.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 179 | 2009-27 | 496.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 180 | 2009-28 | 57.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 181 | 2009-29 | 42.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 182 | 2009-30 | 46.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 183 | 2009-31 | 72.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 184 | 2009-32 | 739.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 185 | 2009-33 | -84.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 186 | 2009-34 | -43.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 187 | 2009-35 | -40.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 188 | 2009-36 | -52.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 189 | 2009-37 | -98.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 190 | 2009-38 | -494.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 191 | 2009-39 | -1251.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 192 | 2009-40 | 472.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 193 | 2009-41 | 454.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 194 | 2009-42 | -4589.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 195 | 2009-43 | -935 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 196 | 2009-44 | -139.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 197 | 2009-45 | -127.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 198 | 2009-46 | -261.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 199 | 2009-47 | 2714.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 200 | 2009-48 | 184.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 201 | 2009-49 | 246.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 202 | 2009-50 | 2632.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 203 | 2009-51 | -492.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 204 | 2009-52 | 47.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 205 | 2009-53 | 19.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 206 | 2010-01 | 46.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 207 | 2010-02 | -137.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 208 | 2010-03 | -25.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 209 | 2010-04 | -26.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 210 | 2010-05 | 931.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 211 | 2010-06 | -3957.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 212 | 2010-07 | -1366.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 213 | 2010-08 | 293.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 214 | 2010-09 | 894.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 215 | 2010-10 | -2238.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 216 | 2010-11 | -254.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 217 | 2010-12 | -112.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 218 | 2010-13 | 32.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 219 | 2010-14 | 47.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 220 | 2010-15 | 278.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 221 | 2010-16 | -65 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 222 | 2010-17 | -27.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 223 | 2010-18 | -198.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 224 | 2010-19 | 120.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 225 | 2010-20 | 102 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 226 | 2010-21 | 107.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 227 | 2010-22 | -1662.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 228 | 2010-23 | -96.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 229 | 2010-24 | -110.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 230 | 2010-25 | -285.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 231 | 2010-26 | 115 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 232 | 2010-27 | 60.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 233 | 2010-28 | 46 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 234 | 2010-29 | 46.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 235 | 2010-30 | 64 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 236 | 2010-31 | 279.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 237 | 2010-32 | -95.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 238 | 2010-33 | -42.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 239 | 2010-34 | -38 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 240 | 2010-35 | -48.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 241 | 2010-36 | -90.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 242 | 2010-37 | -287.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 243 | 2010-38 | -1058.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 244 | 2010-39 | -1748.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 245 | 2010-40 | 348.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 246 | 2010-41 | 347 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 247 | 2010-42 | 1251.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 248 | 2010-43 | 1382.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 249 | 2010-44 | -247.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 250 | 2010-45 | -504.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 251 | 2010-46 | -571.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 252 | 2010-47 | -612.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 253 | 2010-48 | 3330.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 254 | 2010-49 | -548.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 255 | 2010-50 | -274.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 256 | 2010-51 | 130.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 257 | 2010-52 | 28.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 258 | 2011-01 | 60.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 259 | 2011-02 | -400.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 260 | 2011-03 | -42.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 261 | 2011-04 | -35.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 262 | 2011-05 | 884.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 263 | 2011-06 | 630.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 264 | 2011-07 | 743.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 265 | 2011-08 | 223.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 266 | 2011-09 | 266.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 267 | 2011-10 | 1436.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 268 | 2011-11 | -768.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 269 | 2011-12 | -269 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 270 | 2011-13 | -496.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 271 | 2011-14 | -1075.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 272 | 2011-15 | -430.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 273 | 2011-16 | 30.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 274 | 2011-17 | 47.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 275 | 2011-18 | 791.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 276 | 2011-19 | -61.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 277 | 2011-20 | -34.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 278 | 2011-21 | -7086 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 279 | 2011-22 | 120.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 280 | 2011-23 | -947.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 281 | 2011-24 | -802.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 282 | 2011-25 | 1301.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 283 | 2011-26 | -10477.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 284 | 2011-27 | 81.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 285 | 2011-28 | 65.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 286 | 2011-29 | 41.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 287 | 2011-30 | 55.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 288 | 2011-31 | 165.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 289 | 2011-32 | -122.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 290 | 2011-33 | -47.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 291 | 2011-34 | -39.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 292 | 2011-35 | -48.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 293 | 2011-36 | -82.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 294 | 2011-37 | -241.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 295 | 2011-38 | -407.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 296 | 2011-39 | -542.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 297 | 2011-40 | 731.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 298 | 2011-41 | 780 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 299 | 2011-42 | 396.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 300 | 2011-43 | -617.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 301 | 2011-44 | -207.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 302 | 2011-45 | -359.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 303 | 2011-46 | -463.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 304 | 2011-47 | 2214.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 305 | 2011-48 | -965.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 306 | 2011-49 | -395.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 307 | 2011-50 | -271 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 308 | 2011-51 | 1343.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 309 | 2011-52 | 28.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 310 | 2012-01 | 51.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 311 | 2012-02 | 298.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 312 | 2012-03 | -61.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 313 | 2012-04 | -32.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 314 | 2012-05 | 1884 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 315 | 2012-06 | 3530.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 316 | 2012-07 | -2394.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 317 | 2012-08 | 522.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 318 | 2012-09 | 817 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 319 | 2012-10 | 1611.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 320 | 2012-11 | -1363.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 321 | 2012-12 | -295.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 322 | 2012-13 | -354.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 323 | 2012-14 | 30 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 324 | 2012-15 | 42.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 325 | 2012-16 | 235.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 326 | 2012-17 | -65.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 327 | 2012-18 | -33.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 328 | 2012-19 | -1272.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 329 | 2012-20 | 116.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 330 | 2012-21 | -1676.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 331 | 2012-22 | -566.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 332 | 2012-23 | -916.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 333 | 2012-24 | -134.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 334 | 2012-25 | -435.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 335 | 2012-26 | -587 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 336 | 2012-27 | 74.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 337 | 2012-28 | 46.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 338 | 2012-29 | 40 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 339 | 2012-30 | 51.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 340 | 2012-31 | 135.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 341 | 2012-32 | -174.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 342 | 2012-33 | -54.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 343 | 2012-34 | -40.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 344 | 2012-35 | -46.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 345 | 2012-36 | -70.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 346 | 2012-37 | -157.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 347 | 2012-38 | -792.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 348 | 2012-39 | -1451.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 349 | 2012-40 | 415 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 350 | 2012-41 | 287.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 351 | 2012-42 | 1266 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 352 | 2012-43 | 699.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 353 | 2012-44 | -357.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 354 | 2012-45 | -384 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 355 | 2012-46 | -528.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 356 | 2012-47 | -328.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 357 | 2012-48 | -653.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 358 | 2012-49 | -529.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 359 | 2012-50 | -365.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 360 | 2012-51 | -205.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 361 | 2012-52 | 24.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 362 | 2013-01 | 28.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 363 | 2013-02 | 127.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 364 | 2013-03 | -55 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 365 | 2013-04 | -21 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 366 | 2013-05 | -89.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 367 | 2013-06 | 333.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 368 | 2013-07 | 791.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 369 | 2013-08 | 216 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 370 | 2013-09 | 274.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 371 | 2013-10 | 2384 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 372 | 2013-11 | -378.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 373 | 2013-12 | -156.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 374 | 2013-13 | 31.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 375 | 2013-14 | 46 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 376 | 2013-15 | 304.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 377 | 2013-16 | -65.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 378 | 2013-17 | -28.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 379 | 2013-18 | 703.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 380 | 2013-19 | 96.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 381 | 2013-20 | 120.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 382 | 2013-21 | 213.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 383 | 2013-22 | -147.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 384 | 2013-23 | -104.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 385 | 2013-24 | -137.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 386 | 2013-25 | -197.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 387 | 2013-26 | 180.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 388 | 2013-27 | 80.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 389 | 2013-28 | 49.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 390 | 2013-29 | 42.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 391 | 2013-30 | 51.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 392 | 2013-31 | 111.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 393 | 2013-32 | -269.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 394 | 2013-33 | -62.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 395 | 2013-34 | -42.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 396 | 2013-35 | -46.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 397 | 2013-36 | -64.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 398 | 2013-37 | -137.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 399 | 2013-38 | -598.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 400 | 2013-39 | -1656.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 401 | 2013-40 | 374.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 402 | 2013-41 | 432.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 403 | 2013-42 | -1592.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 404 | 2013-43 | -2079.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 405 | 2013-44 | -227.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 406 | 2013-45 | -373.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 407 | 2013-46 | -1341.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 408 | 2013-47 | -837.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 409 | 2013-48 | 253945.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 410 | 2013-49 | -594.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 411 | 2013-50 | -334.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 412 | 2013-51 | -231.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 413 | 2013-52 | 23.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 414 | 2014-01 | 21.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 415 | 2014-02 | 73.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 416 | 2014-03 | -56 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 417 | 2014-04 | -18.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 418 | 2014-05 | -48.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 419 | 2014-06 | 439 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 420 | 2014-07 | -1010.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 421 | 2014-08 | 330 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 422 | 2014-09 | 393.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 423 | 2014-10 | 469 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 424 | 2014-11 | -479.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 425 | 2014-12 | -183 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 426 | 2014-13 | -330.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 427 | 2014-14 | -440.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 428 | 2014-15 | -635.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 429 | 2014-16 | 29.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 430 | 2014-17 | 43.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 431 | 2014-18 | 105 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 432 | 2014-19 | -74.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 433 | 2014-20 | -26.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 434 | 2014-21 | -119.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 435 | 2014-22 | 582.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 436 | 2014-23 | 333.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 437 | 2014-24 | 154.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 438 | 2014-25 | -2119.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 439 | 2014-26 | -388.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 440 | 2014-27 | 100.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 441 | 2014-28 | 73.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 442 | 2014-29 | 40.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 443 | 2014-30 | 46.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 444 | 2014-31 | 90.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 445 | 2014-32 | -295.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 446 | 2014-33 | -58.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 447 | 2014-34 | -38.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 448 | 2014-35 | -42.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 449 | 2014-36 | -64.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 450 | 2014-37 | -133.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 451 | 2014-38 | -480.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 452 | 2014-39 | -4483.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 453 | 2014-40 | 496.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 454 | 2014-41 | 252.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 455 | 2014-42 | 822.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 456 | 2014-43 | -12758.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 457 | 2014-44 | -284.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 458 | 2014-45 | -296.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 459 | 2014-46 | -741.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 460 | 2014-47 | -724.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 461 | 2014-48 | -3954 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 462 | 2014-49 | -457.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 463 | 2014-50 | -322.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 464 | 2014-51 | -221.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 465 | 2014-52 | 29.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 466 | 2015-01 | 19.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 467 | 2015-02 | 57.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 468 | 2015-03 | -69 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 469 | 2015-04 | -20.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 470 | 2015-05 | -32.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 471 | 2015-06 | 426.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 472 | 2015-07 | -1888.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 473 | 2015-08 | 304.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 474 | 2015-09 | 276 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 475 | 2015-10 | 413.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 476 | 2015-11 | -1497 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 477 | 2015-12 | -259.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 478 | 2015-13 | -412.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 479 | 2015-14 | 30 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 480 | 2015-15 | 43.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 481 | 2015-16 | 314.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 482 | 2015-17 | -60.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 483 | 2015-18 | -31.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 484 | 2015-19 | -386.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 485 | 2015-20 | 123.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 486 | 2015-21 | -3449.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 487 | 2015-22 | 4693 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 488 | 2015-23 | -1058.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 489 | 2015-24 | -133.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 490 | 2015-25 | -670.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 491 | 2015-26 | -335.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 492 | 2015-27 | 95 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 493 | 2015-28 | 52.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 494 | 2015-29 | 40.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 495 | 2015-30 | 42.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 496 | 2015-31 | 70.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 497 | 2015-32 | -693 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 498 | 2015-33 | -62.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 499 | 2015-34 | -39.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 500 | 2015-35 | -40.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 501 | 2015-36 | -62 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 502 | 2015-37 | -136.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 503 | 2015-38 | -572.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 504 | 2015-39 | -1132.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 505 | 2015-40 | 666.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 506 | 2015-41 | 438.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 507 | 2015-42 | 22566.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 508 | 2015-43 | -1780.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 509 | 2015-44 | -248.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 510 | 2015-45 | -316.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 511 | 2015-46 | -560.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 512 | 2015-47 | -712.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 513 | 2015-48 | 1044.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 514 | 2015-49 | -2025.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 515 | 2015-50 | -531.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 516 | 2015-51 | -274.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 517 | 2015-52 | 51 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 518 | 2015-53 | 20.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 519 | 2016-01 | 50.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 520 | 2016-02 | -134.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 521 | 2016-03 | -27.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 522 | 2016-04 | -28.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 523 | 2016-05 | 1652.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 524 | 2016-06 | -436.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 525 | 2016-07 | -631.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 526 | 2016-08 | 237 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 527 | 2016-09 | 331 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 528 | 2016-10 | 841.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 529 | 2016-11 | -263.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 530 | 2016-12 | 35.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 531 | 2016-13 | 45.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 532 | 2016-14 | 379.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 533 | 2016-15 | -67.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 534 | 2016-16 | -28.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 535 | 2016-17 | -174.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 536 | 2016-18 | 121.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 537 | 2016-19 | 396.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 538 | 2016-20 | 66.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 539 | 2016-21 | 272.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 540 | 2016-22 | -129.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 541 | 2016-23 | -147.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 542 | 2016-24 | -66.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 543 | 2016-25 | 316.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 544 | 2016-26 | 125.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 545 | 2016-27 | 60.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 546 | 2016-28 | 43.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 547 | 2016-29 | 40.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 548 | 2016-30 | 55.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 549 | 2016-31 | 260.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 550 | 2016-32 | -93.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 551 | 2016-33 | -43 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 552 | 2016-34 | -38 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 553 | 2016-35 | -49.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 554 | 2016-36 | -84.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 555 | 2016-37 | -239.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 556 | 2016-38 | 32422.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 557 | 2016-39 | -4327 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 558 | 2016-40 | 358.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 559 | 2016-41 | 384.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 560 | 2016-42 | -2644.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 561 | 2016-43 | 10423.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 562 | 2016-44 | -241.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 563 | 2016-45 | -666.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 564 | 2016-46 | -1432.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 565 | 2016-47 | -480.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 566 | 2016-48 | -597.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 567 | 2016-49 | -268.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 568 | 2016-50 | -278.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 569 | 2016-51 | 1416.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 570 | 2016-52 | 28.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 571 | 2017-01 | 51.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 572 | 2017-02 | 951.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 573 | 2017-03 | -55.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 574 | 2017-04 | -31.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 575 | 2017-05 | 14549.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 576 | 2017-06 | 797.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 577 | 2017-07 | 1583.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 578 | 2017-08 | 193.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 579 | 2017-09 | 205.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 580 | 2017-10 | 830.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 581 | 2017-11 | -647.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 582 | 2017-12 | -206.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 583 | 2017-13 | -341 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 584 | 2017-14 | -301.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 585 | 2017-15 | 29.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 586 | 2017-16 | 42.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 587 | 2017-17 | 230.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 588 | 2017-18 | -101.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 589 | 2017-19 | -27.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 590 | 2017-20 | -1738.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 591 | 2017-21 | 153.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 592 | 2017-22 | -255.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 593 | 2017-23 | 237.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 594 | 2017-24 | -171 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 595 | 2017-25 | -177.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 596 | 2017-26 | 273.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 597 | 2017-27 | 124.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 598 | 2017-28 | 41.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 599 | 2017-29 | 35.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 600 | 2017-30 | 48.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 601 | 2017-31 | 155 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 602 | 2017-32 | -111.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 603 | 2017-33 | -45.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 604 | 2017-34 | -39 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 605 | 2017-35 | -48 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 606 | 2017-36 | -75.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 607 | 2017-37 | -176.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 608 | 2017-38 | -525.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 609 | 2017-39 | -955.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 610 | 2017-40 | 412.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 611 | 2017-41 | 331.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 612 | 2017-42 | 615.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 613 | 2017-43 | -580.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 614 | 2017-44 | -204.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 615 | 2017-45 | -285.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 616 | 2017-46 | -584.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 617 | 2017-47 | 1657.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 618 | 2017-48 | -2254.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 619 | 2017-49 | -737.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 620 | 2017-50 | -350.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 621 | 2017-51 | -503.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 622 | 2017-52 | 24.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 623 | 2018-01 | 35.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 624 | 2018-02 | 202.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 625 | 2018-03 | -53.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 626 | 2018-04 | -23.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 627 | 2018-05 | -139.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 628 | 2018-06 | -3750.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 629 | 2018-07 | -6671.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 630 | 2018-08 | 179.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 631 | 2018-09 | 205.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 632 | 2018-10 | 991.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 633 | 2018-11 | -496.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 634 | 2018-12 | -151.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 635 | 2018-13 | 30.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 636 | 2018-14 | 44.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 637 | 2018-15 | 423.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 638 | 2018-16 | -64.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 639 | 2018-17 | -27.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 640 | 2018-18 | 441.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 641 | 2018-19 | 90 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 642 | 2018-20 | 89.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 643 | 2018-21 | 156.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 644 | 2018-22 | -131.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 645 | 2018-23 | -87.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 646 | 2018-24 | -91 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 647 | 2018-25 | -199.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 648 | 2018-26 | 152.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 649 | 2018-27 | 63.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 650 | 2018-28 | 40.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 651 | 2018-29 | 36.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 652 | 2018-30 | 47.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 653 | 2018-31 | 166.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 654 | 2018-32 | -106.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 655 | 2018-33 | -47.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 656 | 2018-34 | -40 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 657 | 2018-35 | -49.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 658 | 2018-36 | -73.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 659 | 2018-37 | -144.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 660 | 2018-38 | -351.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 661 | 2018-39 | -1021.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 662 | 2018-40 | 358.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 663 | 2018-41 | 315 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 664 | 2018-42 | -16274.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 665 | 2018-43 | -1203.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 666 | 2018-44 | -240.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 667 | 2018-45 | -365.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 668 | 2018-46 | -650.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 669 | 2018-47 | -761.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 670 | 2018-48 | 6924.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 671 | 2018-49 | -605.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 672 | 2018-50 | -338.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 673 | 2018-51 | -252.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 674 | 2018-52 | 20.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 675 | 2019-01 | 23.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 676 | 2019-02 | 99.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 677 | 2019-03 | -45.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 678 | 2019-04 | -17.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 679 | 2019-05 | -66.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 680 | 2019-06 | 1067.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 681 | 2019-07 | -770.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 682 | 2019-08 | 321.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 683 | 2019-09 | 258.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 684 | 2019-10 | 612.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 685 | 2019-11 | -961.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 686 | 2019-12 | -251.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 687 | 2019-13 | -589.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 688 | 2019-14 | -2283.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 689 | 2019-15 | -524.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 690 | 2019-16 | 28.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 691 | 2019-17 | 44.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 692 | 2019-18 | 143.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 693 | 2019-19 | -65.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 694 | 2019-20 | -30.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 695 | 2019-21 | -218 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 696 | 2019-22 | 354.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 697 | 2019-23 | 13295.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 698 | 2019-24 | 1199.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 699 | 2019-25 | -5247.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 700 | 2019-26 | -322.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 701 | 2019-27 | 98.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 702 | 2019-28 | 61.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 703 | 2019-29 | 34.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 704 | 2019-30 | 43.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 705 | 2019-31 | 111.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 706 | 2019-32 | -132.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 707 | 2019-33 | -49.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 708 | 2019-34 | -38.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 709 | 2019-35 | -46.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 710 | 2019-36 | -73.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 711 | 2019-37 | -165.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 712 | 2019-38 | -566.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 713 | 2019-39 | -1081.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 714 | 2019-40 | 441.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 715 | 2019-41 | 294.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 716 | 2019-42 | -5397.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 717 | 2019-43 | -539.3 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 718 | 2019-44 | -187.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 719 | 2019-45 | -324.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 720 | 2019-46 | -14255.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 721 | 2019-47 | -679.9 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 722 | 2019-48 | -1261.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 723 | 2019-49 | -545.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 724 | 2019-50 | -336.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 725 | 2019-51 | -252.8 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 726 | 2019-52 | 22.4 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 727 | 2020-01 | 20.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 728 | 2020-02 | 69.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 729 | 2020-03 | -50.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 730 | 2020-04 | -17.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 731 | 2020-05 | -43.7 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 732 | 2020-06 | 534.5 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 733 | 2020-07 | -1379.1 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 734 | 2020-08 | 218.2 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 735 | 2020-09 | 213.6 | NA | 2 | every count is 0 |
| real_covid19 | numerator_vs_denominator_doublingdays0_34 | 736 | 2020-10 | 0.2 | NA | 4 | separated |
