# The names v4 creates: at most 63 bytes in UTF-8, distinct in their first 63
# bytes, and no base measure that ends in a reserved suffix.

test_that("a name of 64 bytes is an error, and one of 63 bytes is not", {
  expect_silent(.v4_check_names(strrep("a", 63)))
  expect_error(.v4_check_names(strrep("a", 64)), "longer than 63 bytes")
})

test_that("the limit counts bytes in UTF-8, not characters", {
  # "æ" is 2 bytes in UTF-8
  expect_silent(.v4_check_names(paste0(strrep("a", 61), "æ")))
  expect_error(
    .v4_check_names(paste0(strrep("a", 62), "æ")),
    "longer than 63 bytes"
  )
  expect_error(.v4_check_names(strrep("æ", 32)), "longer than 63 bytes")
})

test_that("two names equal in their first 63 bytes are an error", {
  # A name over 63 bytes is already an error, so two names that pass the
  # length rule and are equal in their first 63 bytes are the same name.
  base <- strrep("b", 62)
  expect_error(
    .v4_check_names(c(paste0(base, "x"), "y", paste0(base, "x"))),
    "equal in their first 63 bytes"
  )
  expect_silent(.v4_check_names(c(paste0(base, "x"), paste0(base, "y"))))
  # the cut is in bytes, and two names that differ after byte 63 are equal
  cut <- .v4_first_bytes(c(paste0(base, "xy"), paste0(base, "xz")), 63L)
  expect_identical(cut[1], cut[2])
  expect_identical(nchar(cut[1]), 126L)
})

test_that(".v4_check_names rejects NA and a non-character", {
  expect_error(.v4_check_names(c("a", NA)), "no NA")
  expect_error(.v4_check_names(1), "character")
})

test_that("a measure name that ends in a reserved suffix is an error", {
  for (s in .V4_RESERVED_SUFFIXES) {
    expect_error(.v4_check_measure_names(paste0("cases", s)), "reserved suffix")
  }
  # The suffixes again, written out, so that a suffix removed from
  # .V4_RESERVED_SUFFIXES makes its rejection fail.
  for (s in c("_trend_beta1", "_trend_se", "_trend_gr", "_trend_pinc")) {
    expect_error(.v4_check_measure_names(paste0("cases", s)), "reserved suffix")
  }
  for (s in c("_mem", "_hlm")) {
    expect_error(.v4_check_measure_names(paste0("cases", s)), "reserved suffix")
  }
  expect_silent(.v4_check_measure_names(c("cases", "cases_trend", "mem_n")))
  expect_identical(
    .V4_RESERVED_SUFFIXES,
    c("_trend_beta1", "_trend_se", "_trend_gr", "_trend_pinc", "_mem", "_hlm")
  )
})

test_that("the naming copies give the same result as v3", {
  p <- c(seq(0, 0.999, by = 0.001), NA, 1, 0.0125)
  expect_identical(.v4_q_label(p), q_label(p))
  lab <- c(q_label(seq(0, 0.999, by = 0.001)), "q100x0", "x", NA)
  expect_identical(.v4_q_value(lab), q_value(lab))
  args <- list(
    list("numerator"),
    list("numerator", role = "observed"),
    list("numerator", q = 0.025),
    list("cases", denom = "pop", per = 100, q = 0.5),
    list("cases", level = "high", suffix = "_n")
  )
  for (a in args) {
    expect_identical(do.call(.v4_var, a), do.call(csfmt_var, a))
  }
  expect_error(.v4_var("x", q = 0.5, level = "a"), "not both")
  for (x in c(
    "cases_pr100_q50x0",
    "cases_q50x0_pr100",
    "cases_status_prob_high",
    "cases_n",
    "cases"
  )) {
    expect_identical(
      .v4_strip_coordinates(x),
      csalert:::csfmt_strip_coordinates(x)
    )
  }
})

test_that(".v4_var errors on a name over 63 bytes", {
  expect_error(.v4_var(strrep("a", 60), q = 0.5), "longer than 63 bytes")
})
