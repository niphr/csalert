# .v4_with_seed() runs an expression after set.seed(), and then puts back the
# random-number state of the caller.

test_that(".v4_with_seed gives the draws of set.seed() and restores the state", {
  set.seed(4)
  want <- stats::runif(3)
  set.seed(77)
  before <- get(".Random.seed", envir = globalenv())
  got <- .v4_with_seed(4, stats::runif(3))
  expect_identical(got, want)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that(".v4_with_seed leaves no .Random.seed when the caller had none", {
  env <- globalenv()
  had <- exists(".Random.seed", envir = env, inherits = FALSE)
  if (had) {
    saved <- get(".Random.seed", envir = env)
    rm(".Random.seed", envir = env)
  }
  .v4_with_seed(4, stats::runif(1))
  absent <- !exists(".Random.seed", envir = env, inherits = FALSE)
  if (had) {
    assign(".Random.seed", saved, envir = env)
  }
  expect_true(absent)
})

test_that(".v4_with_seed restores the state when the expression errors", {
  set.seed(5)
  before <- get(".Random.seed", envir = globalenv())
  expect_error(
    .v4_with_seed(4, {
      stats::runif(2)
      stop("boom", call. = FALSE)
    }),
    "boom"
  )
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that(".v4_with_seed needs one whole number", {
  expect_error(.v4_with_seed(NULL, 1), "one whole number")
  expect_error(.v4_with_seed(c(1, 2), 1), "one whole number")
  expect_error(.v4_with_seed(NA_real_, 1), "one whole number")
  expect_error(.v4_with_seed("4", 1), "one whole number")
  expect_identical(.v4_with_seed(4L, "x"), "x")
})
