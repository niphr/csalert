# Assign content-hash time_series_id (+ readable label) by reference

Assign content-hash time_series_id (+ readable label) by reference

## Usage

``` r
set_time_series_id(d, id_cols, sep = "\037")
```

## Arguments

- d:

  data.table.

- id_cols:

  Character vector of identity columns defining a series.

- sep:

  Separator for the canonical key (default unit-separator).

## Value

\`d\`, modified by reference (invisibly).
