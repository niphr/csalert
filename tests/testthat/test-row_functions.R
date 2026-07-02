# row_mean / row_sd helpers.

test_that("row_mean matches rowMeans and row_sd matches per-row sd", {
  m <- matrix(c(1, 2, 3,
                4, 5, 6,
                7, 8, 9,
                10, 11, 12), ncol = 3, byrow = TRUE)
  expect_equal(row_mean(m), rowMeans(m))
  expect_equal(row_sd(m), apply(m, 1, stats::sd))
})
