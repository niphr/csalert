# Naming grammar: q_label/q_value and csfmt_var/csfmt_parse.

test_that("q_label maps probabilities to controlled-vocabulary labels", {
  expect_equal(q_label(0.025), "q02x5")
  expect_equal(q_label(0.5),   "q50x0")
  expect_equal(q_label(0.975), "q97x5")
  expect_equal(q_label(0.005), "q00x5")
  expect_equal(q_label(0.995), "q99x5")
  expect_equal(q_label(0.05),  "q05x0")
  expect_equal(q_label(c(0.025, 0.5, 0.975)), c("q02x5", "q50x0", "q97x5"))
})

test_that("q_value inverts q_label", {
  probs <- c(0.005, 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975, 0.995)
  expect_equal(q_value(q_label(probs)), probs)
})

test_that("csfmt_var builds the canonical names", {
  expect_equal(csfmt_var("consults_r80", denom = "all", per = 100),
               "consults_r80_vs_all_pr100")
  expect_equal(csfmt_var("cases", role = "forecasted", q = 0.025, suffix = "_n"),
               "cases_forecasted_q02x5_n")
  expect_equal(csfmt_var("cases", role = "status", level = "high"),
               "cases_status_prob_high")
  expect_equal(csfmt_var("cases", role = "status", q = 0.5),
               "cases_status_q50x0")
  expect_equal(csfmt_var("cases", suffix = "_n"), "cases_n")
})

test_that("csfmt_var rejects q and level together", {
  expect_error(csfmt_var("cases", q = 0.5, level = "high"), "not both")
})

test_that("csfmt_parse inverts csfmt_var (round-trip)", {
  cases <- list(
    list(measure = "consults_r80", denom = "all", per = 100L),
    list(measure = "cases", role = "forecasted", q = 0.025, suffix = "_n"),
    list(measure = "cases", role = "status", level = "high"),
    list(measure = "cases", role = "status", q = 0.5),
    list(measure = "cases", role = "trend", suffix = "_n"),
    list(measure = "consults_r80", denom = "all", role = "nowcasted", q = 0.975, per = 100L)
  )
  for (cm in cases) {
    nm <- do.call(csfmt_var, cm)
    parsed <- csfmt_parse(nm)
    expect_equal(parsed[names(cm)], cm[names(cm)], info = nm)
  }
})

test_that("csfmt_parse handles a bare measure", {
  expect_equal(csfmt_parse("cases"), list(measure = "cases"))
})
