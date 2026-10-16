# csfmt_ensemble_v4 holds its slots as list elements, and matches the row
# order and the ids of csfmt_ensemble_v3.

v4_ens_input <- function() {
  d <- data.table::data.table(
    location_code = rep(c("nation", "county03"), each = 4),
    age = "total",
    isoyearweek = rep(c("2023-04", "2023-01", "2023-03", "2023-02"), 2)
  )
  set.seed(1)
  m <- matrix(stats::rpois(8 * 5, 20), nrow = 8)
  s <- matrix(sample(1:3, 8 * 5, replace = TRUE), nrow = 8)
  attr(s, "levels") <- c("low", "mid", "high")
  return(list(d = d, draws = list(cases = m, cases_status = s)))
}

test_that("csfmt_ensemble_v4 holds its slots as list elements", {
  x <- v4_ens_input()
  e <- csfmt_ensemble_v4(
    x$d,
    id_cols = c("location_code", "age"),
    draws = x$draws
  )
  expect_s3_class(e, "csfmt_ensemble_v4")
  expect_identical(names(e), c("data", "draws", "id_cols", "time_col", "state"))
  expect_identical(e$id_cols, c("location_code", "age"))
  expect_identical(e$time_col, "isoyearweek")
  expect_identical(e$state, "full")
  # the slots survive unclass(), which drops the class attribute
  expect_identical(unclass(e)$state, "full")
})

test_that("csfmt_ensemble_v4 sorts data and draws as csfmt_ensemble_v3 does", {
  x <- v4_ens_input()
  id <- c("location_code", "age")
  e3 <- csfmt_ensemble_v3(x$d, id_cols = id, draws = x$draws)
  e4 <- csfmt_ensemble_v4(x$d, id_cols = id, draws = x$draws)
  expect_identical(e4$data, e3$data)
  expect_identical(e4$draws, e3$draws)
  expect_identical(
    attr(e4$draws$cases_status, "levels"),
    c("low", "mid", "high")
  )
  # the input is not changed
  expect_false("time_series_id" %in% names(x$d))
})

test_that("csfmt_ensemble_v4 rejects a bad draw matrix and a long name", {
  x <- v4_ens_input()
  id <- c("location_code", "age")
  expect_error(
    csfmt_ensemble_v4(x$d, id_cols = id, draws = list(a = matrix(1, 3, 2))),
    "must be a matrix with 8 rows"
  )
  long <- list(matrix(1, 8, 2))
  names(long) <- strrep("a", 64)
  expect_error(
    csfmt_ensemble_v4(x$d, id_cols = id, draws = long),
    "longer than 63 bytes"
  )
  expect_error(csfmt_ensemble_v4(x$d, id_cols = "nope"))
})

test_that(".v4_validate_ensemble checks the state and the slots", {
  x <- v4_ens_input()
  e <- csfmt_ensemble_v4(
    x$d,
    id_cols = c("location_code", "age"),
    draws = x$draws
  )
  bad <- e
  bad$state <- "compressed"
  expect_error(.v4_validate_ensemble(bad), "state")
  bad <- e
  bad$time_col <- "date"
  expect_error(.v4_validate_ensemble(bad), "misses date")
  bad <- e
  bad$draws$cases <- bad$draws$cases[-1, ]
  expect_error(.v4_validate_ensemble(bad), "must be a matrix with 8 rows")
  bad <- e
  bad$data <- data.table::copy(e$data)[, cases := 1]
  expect_error(.v4_validate_ensemble(bad), "equal in their first 63 bytes")
  expect_identical(.v4_validate_ensemble(e), e)
})

test_that("print shows the state, the rows, the series and the draws", {
  x <- v4_ens_input()
  e <- csfmt_ensemble_v4(
    x$d,
    id_cols = c("location_code", "age"),
    draws = x$draws
  )
  expect_output(
    print(e),
    "<csfmt_ensemble_v4> full | 8 rows | 2 series | draws: cases, cases_status",
    fixed = TRUE
  )
  e0 <- csfmt_ensemble_v4(x$d, id_cols = c("location_code", "age"))
  expect_output(print(e0), "draws: none", fixed = TRUE)
})
