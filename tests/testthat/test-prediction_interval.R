# prediction_interval.glm (Benedetti skewness-transformed PI for (quasi)poisson).

test_that("returns ordered lower <= point <= upper for a quasipoisson glm", {
  set.seed(1)
  x <- 1:50
  y <- stats::rpois(50, lambda = exp(1 + 0.05 * x))
  m <- stats::glm(y ~ x, family = stats::quasipoisson(link = "log"))

  pi <- prediction_interval(m, data.frame(x = 51:55))

  expect_true(all(c("lower", "point", "upper") %in% names(pi)))
  expect_equal(nrow(pi), 5L)
  expect_true(all(pi$lower <= pi$point, na.rm = TRUE))
  expect_true(all(pi$point <= pi$upper, na.rm = TRUE))
})

test_that("rejects non-(quasi)poisson families", {
  m <- stats::glm(c(1, 0, 1, 0) ~ c(1, 2, 3, 4), family = stats::binomial())
  expect_error(prediction_interval(m, data.frame(x = 1)))
})
