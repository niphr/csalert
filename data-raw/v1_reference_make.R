# Build the v1 short_term_trend() reference fixture.
#
# Run it from the package root, on an unchanged checkout:
#   Rscript data-raw/v1_reference_make.R
#
# The script loads this checkout with pkgload::load_all() and runs today's v1
# method on each input. It saves the inputs, the arguments and the outputs to
# tests/testthat/fixtures/v1_reference.rds. A case where v1 stops
# stores the error message as its expected outcome.
#
# The real-data cases read the norsyss export on the FHI file share. They keep
# only aggregated national weekly counts.

stopifnot(
  file.exists("DESCRIPTION"),
  read.dcf("DESCRIPTION")[, "Package"] == "csalert"
)
pkgload::load_all(".", quiet = TRUE)
library(data.table)

fixture <- file.path("tests", "testthat", "fixtures", "v1_reference.rds")
real_csv <- paste0(
  "//fhi.no/Fil/Styrt/fra_norsyss_til_luftveisovervaking/_interactive/",
  "data_til_trendmodell/norsyss_respiratory_v1_2026-10-13.csv"
)

# Run v1 on a copy of `input`. Record every warning, and the error message if
# v1 stops.
run_v1 <- function(input, args) {
  warnings <- character()
  error <- NULL
  start <- proc.time()[["elapsed"]]
  output <- tryCatch(
    withCallingHandlers(
      do.call(short_term_trend, c(list(data.table::copy(input)), args)),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )
  list(
    output = output,
    warnings = warnings,
    error = error,
    seconds = proc.time()[["elapsed"]] - start
  )
}

# A weekly series of `n_weeks` weeks from 2020-01, in the shape of the test
# helper gen_weekly_skeleton().
skeleton <- function(n_weeks = 20, location = "nation_nor") {
  weeks <- cstime::dates_by_isoyearweek[isoyear == 2020]$isoyearweek
  cstidy::csfmt_rts_data_v1(data.table(
    granularity_time = "isoyearweek",
    location_code = location,
    isoyearweek = weeks[seq_len(n_weeks)],
    age = "total",
    sex = "total",
    border = 2020
  ))
}

series <- function(numerator, denominator, location = "nation_nor") {
  d <- skeleton(length(numerator), location)
  d[, numerator_n := as.integer(numerator)]
  d[, denominator_n := as.integer(denominator)]
  d[]
}

# The norsyss.cs9 call. Each case changes at most a few of these.
base_args <- list(
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

set.seed(20261016)
t20 <- 1:20
den20 <- function() rpois(20, 2000)
num <- list(
  rising = rpois(20, 10 * exp(0.15 * t20)),
  falling = rpois(20, 200 * exp(-0.15 * t20)),
  flat = rpois(20, 50),
  allzero = replace(rpois(20, 20), 6:14, 0L),
  separated = c(4, 3, 5, 0, 0, 0, 0, 5, 6, 4, 1, 0, 0, 0, 0, 3, 4, 5, 6, 4),
  na_inside = replace(rpois(20, 30), c(7, 12, 13), NA),
  few_nonna = replace(rpois(20, 30), 8:12, NA),
  last_window_na = replace(rpois(20, 10 * exp(0.15 * t20)), 16:20, NA)
)
den <- lapply(num, function(x) den20())

zero_den <- den20()
zero_den[c(5, 9, 10, 19)] <- 0L

# The list of cases: name -> input and arguments.
specs <- list()
add <- function(name, input, args = list(), with_denominator = c(TRUE, FALSE)) {
  for (has_den in with_denominator) {
    a <- utils::modifyList(base_args, args)
    if (!has_den) {
      a$denominator <- NULL
    }
    suffix <- if (has_den) "_den" else "_noden"
    specs[[paste0(name, suffix)]] <<- list(input = input, args = a)
  }
}

for (nm in c(
  "rising",
  "falling",
  "flat",
  "allzero",
  "separated",
  "na_inside",
  "few_nonna",
  "last_window_na"
)) {
  add(nm, series(num[[nm]], den[[nm]]))
}
rising <- series(num$rising, den$rising)
add("zero_denominator", series(num$rising, zero_den), with_denominator = TRUE)
add("width2", rising, list(trend_isoyearweeks = 2))
add("width6", rising, list(trend_isoyearweeks = 6))
add("decreasing_rising", rising, list(include_decreasing = TRUE))
add(
  "decreasing_falling",
  series(num$falling, den$falling),
  list(include_decreasing = TRUE)
)
add(
  "decreasing_flat",
  series(num$flat, den$flat),
  list(include_decreasing = TRUE)
)
add("remove_last1", rising, list(remove_last_isoyearweeks = 1))
add("forecast0", rising, list(forecast_isoyearweeks = 0))
add("prx_100_1000", rising, list(prX = c(100, 1000)), with_denominator = TRUE)
add("missing_week", rising[-10])

two_series <- rbind(
  series(num$rising, den$rising, "nation_nor"),
  series(num$falling, den$falling, "county_nor03")
)
cstidy::set_csfmt_rts_data_v1(two_series)
add("two_series", two_series)

unequal <- rbind(
  series(num$rising, den$rising, "nation_nor"),
  series(num$falling[1:15], den$falling[1:15], "county_nor03")
)
cstidy::set_csfmt_rts_data_v1(unequal)
add("two_series_unequal", unequal)

# The real data: one call per ICPC-2 group, as norsyss.cs9 runs it. The three
# groups all have includes_influenza_covid19 TRUE in norsyss.cs9's icpc2 table
# (R/00_data_icpc2.R), so the denominator is consultations_all_n.
real <- fread(real_csv)
real <- real[
  icpc2grp_tag %in%
    c("r80", "respiratory_infections", "covid19") &
    granularity_geo == "nation" &
    tariffgroup_tag == "fe"
]
real[, date := as.Date(date)]
real[, calyear := as.integer(calyear)]
real[, calmonth := as.integer(calmonth)]
real[, calyearmonth := as.character(calyearmonth)]
for (tag in c("r80", "respiratory_infections", "covid19")) {
  d <- copy(real[icpc2grp_tag == tag])
  cstidy::set_csfmt_rts_data_v1(d)
  setnames(d, "consultations_icpc2group_n", "numerator_n")
  setnames(d, "consultations_all_n", "denominator_n")
  specs[[paste0("real_", tag)]] <- list(input = d, args = base_args)
}

cases <- lapply(names(specs), function(nm) {
  s <- specs[[nm]]
  r <- run_v1(s$input, s$args)
  outcome <- if (is.null(r$error)) {
    sprintf("%d rows", nrow(r$output))
  } else {
    paste("ERROR:", r$error)
  }
  cat(sprintf(
    "%-28s input %5d rows, %6.2f s, %d warnings, %s\n",
    nm,
    nrow(s$input),
    r$seconds,
    length(r$warnings),
    outcome
  ))
  list(
    input = s$input,
    args = s$args,
    output = r$output,
    warnings = r$warnings,
    error = r$error,
    seconds = r$seconds
  )
})
names(cases) <- names(specs)

meta <- list(
  R = R.version.string,
  glm2 = as.character(utils::packageVersion("glm2")),
  cstidy = as.character(utils::packageVersion("cstidy")),
  data.table = as.character(utils::packageVersion("data.table")),
  csalert = as.character(utils::packageVersion("csalert")),
  git_head = system("git rev-parse HEAD", intern = TRUE),
  made = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
)
str(meta)

dir.create(dirname(fixture), showWarnings = FALSE, recursive = TRUE)
saveRDS(list(meta = meta, cases = cases), fixture, compress = "xz")
size <- file.size(fixture)
cat(sprintf("%s: %d bytes\n", fixture, size))
if (size > 1e6) {
  stop("The fixture exceeds 1 MB. Split it per case.", call. = FALSE)
}
