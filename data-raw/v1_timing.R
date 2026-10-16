# Time the v1 short_term_trend() table method, old path against new path.
#
# Run it from the package root:
#   Rscript data-raw/v1_timing.R [n_locations]
#
# The old path is R/short_term_trend.R of csalert 94100f5, which fits two glm2
# models in every window. The new path is this checkout, which fits every
# window with .v4_rolling_qp_offset(). The script reports seconds and the
# number of glm2::glm2() calls in each run. It stops if the new path calls
# glm2.
#
# The data are one synthetic ICPC-2 group in the shape that norsyss.cs9 sends.
# It has 28 locations (1 nation, 12 georegions, 15 counties) x 9 ages, which
# is 252 series of 1,000 weeks. The numerator is Poisson with a seasonal rate
# per consultation, and the denominator is Poisson. A smaller n_locations runs
# a faster check.

stopifnot(
  file.exists("DESCRIPTION"),
  read.dcf("DESCRIPTION")[, "Package"] == "csalert"
)
pkgload::load_all(".", quiet = TRUE)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
n_locations <- if (length(args)) as.integer(args[[1]]) else 28L
old_ref <- "94100f5"

# The old path: the functions of the old file, in an environment whose parent
# is the csalert namespace. So the old code calls today's other helpers, such
# as prediction_interval().
old <- new.env(parent = asNamespace("csalert"))
old_src <- system2(
  "git",
  c("show", paste0(old_ref, ":R/short_term_trend.R")),
  stdout = TRUE
)
eval(parse(text = old_src, keep.source = FALSE), envir = old)

# The synthetic group.
set.seed(20261017)
locations <- c(
  "nation_nor",
  sprintf("georegion_nor%02d", 1:12),
  sprintf(
    "county_nor%02d",
    c(3, 11, 15, 18, 31, 32, 33, 34, 39, 40, 42, 46, 50, 55, 56)
  )
)[seq_len(n_locations)]
ages <- c(
  "total",
  "000_004",
  "005_014",
  "015_019",
  "020_029",
  "030_064",
  "065_079",
  "080_084",
  "085p"
)
weeks <- cstime::dates_by_isoyearweek$isoyearweek
weeks <- weeks[seq(which(weeks == "2026-40") - 999L, length.out = 1000L)]
# Weekly consultations per series: the nation is the largest, and a county is
# the smallest. An age band gets a ninth of its location.
size <- c(nation = 200000, georegion = 16000, county = 12000)
d <- CJ(location_code = locations, age = ages, isoyearweek = weeks)
d[, geo := sub("_.*", "", location_code)]
d[, t := match(isoyearweek, weeks)]
d[, mean_den := size[geo] / ifelse(age == "total", 1, 9)]
d[, denominator_n := rpois(.N, mean_den)]
d[, rate := 0.02 * (1 + 0.6 * cos(2 * pi * (t - 5) / 52.18))]
d[, numerator_n := rpois(.N, denominator_n * rate)]
d <- d[, .(
  granularity_time = "isoyearweek",
  location_code,
  isoyearweek,
  age,
  sex = "total",
  numerator_n,
  denominator_n
)]
d <- cstidy::csfmt_rts_data_v1(d)

# The norsyss.cs9 call.
stt_args <- list(
  numerator = "numerator_n",
  denominator = "denominator_n",
  prX = 100,
  trend_isoyearweeks = 5,
  remove_last_isoyearweeks = 0,
  forecast_isoyearweeks = 2,
  numerator_naming_prefix = "generic",
  denominator_naming_prefix = "generic",
  statistics_naming_prefix = "universal",
  remove_training_data = TRUE,
  include_decreasing = FALSE,
  alpha = 0.10
)

# Count the glm2::glm2() calls of each run.
ns_glm2 <- asNamespace("glm2")
counts <- new.env()
counts$glm2 <- 0L
on_glm2 <- function() {
  counts$glm2 <- counts$glm2 + 1L
}
invisible(suppressMessages(trace(
  "glm2",
  tracer = bquote(.(on_glm2)()),
  where = ns_glm2,
  print = FALSE
)))
ns <- asNamespace("csalert")

new_seconds <- system.time(
  new_out <- do.call(
    ns$short_term_trend.csfmt_rts_data_v1,
    c(list(copy(d)), stt_args)
  )
)[["elapsed"]]
new_glm2 <- counts$glm2

counts$glm2 <- 0L
old_seconds <- system.time(
  old_out <- do.call(
    old$short_term_trend.csfmt_rts_data_v1,
    c(list(copy(d)), stt_args)
  )
)[["elapsed"]]
old_glm2 <- counts$glm2
invisible(suppressMessages(untrace("glm2", where = ns_glm2)))

n_series <- length(locations) * length(ages)
cat(sprintf(
  "%d series x %d weeks = %d rows; W = 5, R = 0, F = 2, prX = 100\n",
  n_series,
  length(weeks),
  nrow(d)
))
cat(sprintf(
  "old path (%s): %8.1f s, %d glm2 calls\n",
  old_ref,
  old_seconds,
  old_glm2
))
cat(sprintf(
  "new path:              %8.1f s, %d glm2 calls\n",
  new_seconds,
  new_glm2
))
cat(sprintf("old / new:             %8.1f\n", old_seconds / new_seconds))

# Where the two paths differ. A doubling time is 7 * N * log(2) / slope, so
# where the slope is within convergence noise of 0, the two paths can give
# different huge values.
dd <- grep("_doublingdays0_", names(old_out), value = TRUE)
st <- grep("_status$", names(old_out), value = TRUE)
a <- old_out[[dd]]
b <- new_out[[dd]]
differ <- !((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
other <- setdiff(names(old_out), dd)
cat(
  "every column except the doubling days identical to the old path:",
  identical(old_out[, ..other], new_out[, ..other]),
  "\n"
)
cat(
  "statuses identical to the old path:",
  identical(as.character(old_out[[st]]), as.character(new_out[[st]])),
  "\n"
)
cat(sprintf(
  "doubling days that differ from the old path: %d of %d\n",
  sum(differ),
  length(a)
))
if (any(differ)) {
  cat(sprintf(
    "smallest |old doubling days| among them: %.4g\n",
    min(abs(a[differ]), na.rm = TRUE)
  ))
}
if (new_glm2 != 0L) {
  stop("The new path called glm2::glm2() ", new_glm2, " times.", call. = FALSE)
}
