# Quality-control checks on surveillance input data

Quality-control checks on surveillance input data

## Usage

``` r
qc_surveillance_data(
  d,
  reference_col = "isoyearweek_reference",
  expect_latest = NULL,
  min_rows = 1L
)
```

## Arguments

- d:

  A data.table of one indicator's data.

- reference_col:

  The reference time column (default "isoyearweek_reference").

- expect_latest:

  Optional: the latest reference period that \*should\* be present. If
  \`max(reference) \< expect_latest\`, the feed is flagged stale.

- min_rows:

  Minimum rows required (default 1).

## Value

A list: \`ok\` (logical) and \`reasons\` (character vector; empty if
ok).
