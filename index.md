Features

01

### Short-term trend

Fit a rolling regression over a configurable window of recent weeks to
classify each period as increasing, not increasing, or decreasing,
following the Benedetti (2019) analytics strategy.

02

### Baseline detection

Compare current counts against a historical baseline using a
hierarchical log-linear model, with forecast values and prediction
intervals returned as new columns alongside the original data.

03

### Doubling days

Both trend functions append a doubling-days column that estimates how
many days at the current rate it would take for the count to double,
giving an interpretable speed-of-change measure.

## Overview

[csalert](https://niphr.github.io/csalert/) helps create alerts from
public health surveillance data.
