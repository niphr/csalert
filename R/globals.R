# data.table uses non-standard evaluation, so column names referenced inside
# `[...]` look like undefined globals to R CMD check. Declaring them here keeps
# "checking R code for possible problems" clean without touching the code.
utils::globalVariables(c(
  # "." is data.table's alias for list(), as in d[, .(x = ...)]. It reads as
  # an undefined function to the scan, not as an undefined variable.
  ".",
  ".delay", ".horizon", ".ref", ".season",
  "abs_diff", "change", "cur", "from",
  "hi50", "hi90", "hlm_threshold",
  "i.level", "i.q", "i.role",
  "in50", "in90", "interpretable", "isoyearweek",
  "lag", "level", "lo50", "lo90",
  "med", "mem_n_seasons", "method",
  "original", "period", "point", "prv",
  "quantile_level", "role", "scope", "seasonweek",
  "time_series_id", "time_series_internal_id", "time_series_label",
  "weeks", "years",
  # nowcast_calibration.R
  ".med", "covered", "coverage_raw", "factor", "halfwidth", "hi", "horizon",
  "lo", "predicted", "r", "reference", "truth"
))
