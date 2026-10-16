# The v1 short_term_trend() reference. data-raw/v1_reference_make.R ran the
# v1 method on csalert 94100f5. It stored each input, its arguments and the
# output (or the error) in fixtures/v1_reference.rds. Each test reruns the
# stored call and compares the result to the stored outcome.
#
# In 2026.10.17, v1 moved onto the v4 kernel, and some stored cells changed on
# purpose. fixtures/v1_reference_changes.md lists each changed cell and its
# rule. The inputs and the arguments of those cases did not change. The cases
# width2_allzero_den and width2_allzero_noden are new in 2026.10.17. They hold
# all-zero windows of width 2, and their stored output is that of the
# 2026.10.17 code.

fixture <- test_path("fixtures", "v1_reference.rds")
skip_if_not(file.exists(fixture), "fixtures/v1_reference.rds is missing")
v1_reference <- readRDS(fixture)

# The tolerance for doubling days. A finite value passes when
# |rerun - stored| <= max(V1_ABS_TOL, V1_REL_TOL * |stored|).
V1_REL_TOL <- 1e-6
V1_ABS_TOL <- 1e-8

# Run v1 on a copy of the stored input, and record every warning.
v1_rerun <- function(case) {
  warnings <- character()
  output <- withCallingHandlers(
    do.call(short_term_trend, c(list(data.table::copy(case$input)), case$args)),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(output = output, warnings = warnings)
}

# The series of each row, with the key columns of cstidy::unique_time_series().
v1_series_key <- function(d) {
  ids <- c(
    "granularity_time",
    "granularity_geo",
    "country_iso3",
    "location_code",
    "border",
    "age",
    "sex",
    grep("(_id|_tag)$", names(d), value = TRUE)
  )
  ids <- intersect(ids, names(d))
  do.call(paste, c(lapply(ids, function(i) as.character(d[[i]])), sep = "|"))
}

# The all-zero rule. v1 sorts each series by date, and its window for a week is
# that week's row and the `width - 1` rows before it. A window is all-zero when
# it has at least one non-NA numerator and every non-NA numerator is 0. An
# all-NA window is not all-zero. The function returns a logical per output row.
# Forecast weeks and weeks with no full window are FALSE.
v1_all_zero_rows <- function(case, output) {
  input <- case$input
  width <- case$args$trend_isoyearweeks
  key <- v1_series_key(input)
  y <- input[[case$args$numerator]]
  zero_weeks <- character()
  for (k in unique(key)) {
    j <- which(key == k)
    j <- j[order(input$date[j])]
    for (m in seq_along(j)) {
      if (m < width) {
        next
      }
      v <- y[j[(m - width + 1):m]]
      if (any(!is.na(v)) && all(v[!is.na(v)] == 0)) {
        zero_weeks <- c(zero_weeks, paste(k, input$isoyearweek[j[m]]))
      }
    }
  }
  paste(v1_series_key(output), output$isoyearweek) %in% zero_weeks
}

# The kind of each value: "NA", "NaN", "Inf", "-Inf", or "" when finite.
v1_special <- function(x) {
  out <- rep("", length(x))
  out[is.na(x)] <- "NA"
  out[is.nan(x)] <- "NaN"
  out[x %in% Inf] <- "Inf"
  out[x %in% -Inf] <- "-Inf"
  out
}

test_that("the v1 reference was made with glm2 1.2.1", {
  # A fixture made with another glm2 would define a different reference.
  expect_identical(v1_reference$meta$glm2, "1.2.1")
})

# Compare the rerun of one case to its stored output, with the rules below.
v1_compare <- function(case) {
  rerun <- v1_rerun(case)
  out <- rerun$output
  ref <- case$output

  # Rule: the warnings, the table class and the row count are the same. The
  # column names, their order and the class of each column are the same.
  expect_identical(rerun$warnings, case$warnings)
  expect_identical(class(out), class(ref))
  expect_identical(names(out), names(ref))
  expect_identical(lapply(out, class), lapply(ref, class))
  expect_identical(nrow(out), nrow(ref))

  status_cols <- grep("_status$", names(ref), value = TRUE)
  doubling_cols <- grep("_doublingdays0_", names(ref), value = TRUE)
  other_cols <- setdiff(names(ref), c(status_cols, doubling_cols))
  zero <- v1_all_zero_rows(case, ref)

  # Rule: status columns are identical as character, with identical levels.
  for (col in status_cols) {
    expect_identical(as.character(out[[col]]), as.character(ref[[col]]))
    expect_identical(levels(out[[col]]), levels(ref[[col]]))
  }

  # Rule: in all-zero rows, the doubling days MUST be NA, in the rerun and in
  # the stored output. In every row, NA, NaN and +-Inf MUST sit in the same
  # places, and finite values match within the tolerance above.
  for (col in doubling_cols) {
    a <- out[[col]]
    b <- ref[[col]]
    expect_true(all(v1_special(a[zero]) == "NA"), label = col)
    expect_true(all(v1_special(b[zero]) == "NA"), label = col)
    expect_identical(v1_special(a), v1_special(b), label = col)
    fin <- is.finite(a) & is.finite(b)
    bad <- which(fin)[
      abs(a[fin] - b[fin]) > pmax(V1_ABS_TOL, V1_REL_TOL * abs(b[fin]))
    ]
    expect(
      length(bad) == 0,
      sprintf(
        "%s differs beyond tolerance in rows %s: %s vs stored %s",
        col,
        paste(bad, collapse = ", "),
        paste(a[bad], collapse = ", "),
        paste(b[bad], collapse = ", ")
      )
    )
  }

  # Rule: every other column is identical. These are the counts, the
  # forecasts and their limits, the rates, the forecast markers and the
  # input columns. For numeric columns, the NA, NaN and Inf placement is
  # also checked on its own, which gives a clearer failure.
  for (col in other_cols) {
    if (is.double(ref[[col]])) {
      expect_identical(
        v1_special(out[[col]]),
        v1_special(ref[[col]]),
        label = col
      )
    }
    expect_identical(out[[col]], ref[[col]], label = col)
  }
}

for (case_name in names(v1_reference$cases)) {
  test_that(paste("v1 reference:", case_name), {
    case <- v1_reference$cases[[case_name]]
    if (is.null(case$error)) {
      v1_compare(case)
    } else {
      # Rule: a stored error is the expected outcome. The rerun MUST stop
      # with the same message.
      expect_error(v1_rerun(case), case$error, fixed = TRUE)
    }
  })
}
