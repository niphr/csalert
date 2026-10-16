# The v1 table method fits every window with the v4 kernel,
# .v4_rolling_qp_offset(), and calls no glm2. test-v1_reference.R cannot see
# which code fitted a window. These tests count the calls with trace(), in a
# rerun of every case of fixtures/v1_reference.rds. The tests at the end check
# the forecast interval against prediction_interval.glm().

fixture <- test_path("fixtures", "v1_reference.rds")
skip_if_not(file.exists(fixture), "fixtures/v1_reference.rds is missing")
v1_reference <- readRDS(fixture)

# Run one stored case, and count the calls of glm2::glm2() and of the kernel.
# A case with a stored error MUST stop with that error.
v1_path_counts <- function(case) {
  ns_glm2 <- asNamespace("glm2")
  ns <- asNamespace("csalert")
  counts <- new.env()
  counts$glm2 <- 0L
  counts$kernel <- 0L
  on_glm2 <- function() {
    counts$glm2 <- counts$glm2 + 1L
  }
  on_kernel <- function() {
    counts$kernel <- counts$kernel + 1L
  }
  suppressMessages({
    trace(
      "glm2",
      tracer = bquote(.(on_glm2)()),
      where = ns_glm2,
      print = FALSE
    )
    trace(
      ".v4_rolling_qp_offset",
      tracer = bquote(.(on_kernel)()),
      where = ns,
      print = FALSE
    )
  })
  on.exit(suppressMessages({
    untrace("glm2", where = ns_glm2)
    untrace(".v4_rolling_qp_offset", where = ns)
  }))
  run <- function() {
    do.call(short_term_trend, c(list(data.table::copy(case$input)), case$args))
  }
  if (is.null(case$error)) {
    run()
  } else {
    expect_error(run(), case$error, fixed = TRUE)
  }
  as.list(counts)
}

test_that("trace() counts a glm2::glm2() call", {
  # The counter itself MUST see a call, or a count of 0 below proves nothing.
  counts <- new.env()
  counts$glm2 <- 0L
  ns_glm2 <- asNamespace("glm2")
  suppressMessages(trace(
    "glm2",
    tracer = bquote(.(function() counts$glm2 <- counts$glm2 + 1L)()),
    where = ns_glm2,
    print = FALSE
  ))
  on.exit(suppressMessages(untrace("glm2", where = ns_glm2)))
  glm2::glm2(
    y ~ t,
    family = stats::quasipoisson,
    data = data.frame(y = c(3, 5, 4, 8, 9), t = 1:5)
  )
  expect_identical(counts$glm2, 1L)
})

for (case_name in names(v1_reference$cases)) {
  test_that(paste("v1 calls no glm2:", case_name), {
    case <- v1_reference$cases[[case_name]]
    counts <- v1_path_counts(case)
    expect_identical(counts$glm2, 0L)
    # A case that stops before the fit never reaches the kernel.
    if (is.null(case$error)) {
      expect_gt(counts$kernel, 0L)
    }
  })
}

# The forecast interval. stt_v1_prediction_interval() on the kernel's fit of a
# clean last window MUST equal prediction_interval.glm() on the glm2 fit of the
# same window. The tolerance is 1e-8 relative, for the point and both bounds.
# The windows have 5 rows at weeks 16 to 20 of 22, as v1 scales time.
# `near_zero` and `near_zero_den` have counts near 0, so their lower bounds are
# below 0. `steep` falls 10-fold each week. At 5 of its forecast weeks 21 to
# 40, exp(eta) falls below .Machine$double.eps, where the inverse link gives
# .Machine$double.eps. No reference case reaches such an eta, so the 20 weeks
# ahead are constructed for this test.
v1_pi_windows <- list(
  rising_den = list(
    y = c(93, 110, 104, 146, 152),
    d = c(1969, 1971, 1976, 2013, 1985)
  ),
  rising = list(y = c(93, 110, 104, 146, 152)),
  falling = list(y = c(40, 31, 22, 18, 12)),
  near_zero = list(y = c(1, 0, 2, 0, 1)),
  near_zero_den = list(
    y = c(0, 1, 0, 0, 1),
    d = c(2000, 2010, 1990, 2005, 1998)
  ),
  steep = list(y = c(5000, 500, 50, 5, 1))
)

# The forecast of one window by v1's code and by prediction_interval.glm().
v1_pi_pair <- function(w, t0) {
  tv <- (16:20) / 22
  has_d <- !is.null(w$d)
  d <- if (has_d) w$d else rep(1, 5)
  d0 <- rep(if (has_d) 2000 else 1, length(t0))
  k <- .v4_rolling_qp_offset(
    Y = matrix(w$y),
    OFF = if (has_d) matrix(log(d)) else NULL,
    TT = matrix(tv),
    width = 5,
    na_rm = TRUE,
    extended = TRUE
  )
  fit <- stt_v1_last_fit(k, 5)
  g <- glm2::glm2(
    y ~ tv + offset(log(d)),
    family = stats::quasipoisson(),
    data = data.frame(y = w$y, tv = tv, d = d)
  )
  list(
    fit = fit,
    eta = fit$beta0 + fit$beta1 * t0 + log(d0),
    v1 = stt_v1_prediction_interval(fit, t0, log(d0)),
    glm = prediction_interval(g, data.frame(tv = t0, d = d0))
  )
}

v1_pi_t0 <- function(name) {
  if (name == "steep") (21:40) / 22 else (21:22) / 22
}

for (name in names(v1_pi_windows)) {
  test_that(
    paste("v1 forecast interval equals prediction_interval.glm:", name),
    {
      p <- v1_pi_pair(v1_pi_windows[[name]], v1_pi_t0(name))
      expect_false(is.null(p$fit))
      for (col in c("point", "lower", "upper")) {
        a <- p$v1[[col]]
        b <- p$glm[[col]]
        expect_false(anyNA(a), label = col)
        expect_false(anyNA(b), label = col)
        expect_lte(max(abs(a - b) / abs(b)), 1e-8, label = col)
      }
    }
  )
}

test_that("the v1 forecast lower bound is not clamped at 0", {
  for (name in c("near_zero", "near_zero_den", "steep")) {
    p <- v1_pi_pair(v1_pi_windows[[name]], v1_pi_t0(name))
    expect_lt(min(p$v1$lower), 0, label = name)
  }
})

test_that("exp(eta) falls below .Machine$double.eps in the steep window", {
  # Without this, the steep window would not test the inverse link.
  p <- v1_pi_pair(v1_pi_windows$steep, v1_pi_t0("steep"))
  expect_gt(sum(exp(p$eta) < .Machine$double.eps), 0)
  expect_identical(min(p$v1$point), .Machine$double.eps)
})
