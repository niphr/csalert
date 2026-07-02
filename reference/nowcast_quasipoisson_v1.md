# Nowcast a reporting triangle into an ensemble (quasipoisson reporting regression)

A discriminative (regression) nowcast engine: for each horizon it
regresses the settled total on the counts reported so far (\`total ~
n\[delay 0\] + n\[delay 1\] + ...\`, quasipoisson/identity, no
intercept) and completes the incomplete weeks by simulating from that
fit – parameter uncertainty plus a dispersion-matched negbin. No
per-week magnitude parameter, so it is robust for the recent weeks and
honestly dispersed. Shares the contract \`f(reporting_triangle, ...) -\>
csfmt_ensemble_v3\`.

## Usage

``` r
nowcast_quasipoisson_v1(x, ...)

# S3 method for class 'csfmt_reporting_triangle_v3'
nowcast_quasipoisson_v1(
  x,
  max_delay,
  n_sim = 1000,
  denominator_col = NULL,
  delay_window = 26,
  ...
)
```

## Arguments

- x:

  A \`csfmt_reporting_triangle_v3\`.

- ...:

  Passed to methods.

- max_delay:

  Delay horizon in weeks.

- n_sim:

  Number of nowcast draws.

- denominator_col:

  Optional denominator column to nowcast alongside.

- delay_window:

  Train on only settled weeks within roughly this many weeks (tracks a
  drifting regime). Default 26; \`NULL\` uses all settled weeks.

## Value

A \`csfmt_ensemble_v3\` with one row per reference week and an
\`n_sim\`-column draw matrix of the nowcasted total per week (settled
weeks degenerate at their observed total; incomplete weeks carry the
regression's parameter + dispersion uncertainty). A second measure is
added when \`denominator_col\` is given.
