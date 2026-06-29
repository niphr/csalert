# Holiday effect —-

The effect of public holiday on a time series of daily counts

## Usage

``` r
add_holiday_effect(data, holiday_data, holiday_effect = 2)
```

## Arguments

- data:

  A csfmt_rds data object

- holiday_data:

  dates

- holiday_effect:

  Ending date of the simulation period.

## Value

A csfmt_rts_data_v1, data.table containing
