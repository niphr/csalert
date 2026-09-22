# The full fyrtarn-style path end-to-end:
# triangle(num+denom) -> nowcast -> add_rate (% positive) -> mem_thresholds_v1 -> collapse.

skip_if_not_installed("mem")

test_that("num + denom nowcast -> rate -> MEM -> collapse runs end-to-end", {
  set.seed(1)
  # ~10 complete seasons of weekly sentinel data, every report at delay day 0
  # 2008-08-04 is a Monday, so every date below is a reference week's own
  # Monday. Reporting on that Monday is delay day 0.
  mondays_all <- as.Date("2008-08-04") + 7 * (0:(12 * 53 - 1))
  iyw_all <- cstime::date_to_isoyearweek_c(mondays_all)
  season <- cstime::isoyearweek_to_season_c(iyw_all)
  cnt <- table(season); keep <- sort(names(cnt)[cnt >= 50])[1:10]
  sel <- season %in% keep
  iyw <- iyw_all[sel]; monday <- mondays_all[sel]

  w <- as.integer(substr(iyw, 6, 7)); dist <- pmin(abs(w - 1), abs(w - 53))
  prevalence <- 0.02 + 0.40 * exp(-(dist^2) / 50)        # seasonal % positive, winter peak
  denom <- stats::rpois(length(iyw), 40) + 20
  num   <- stats::rbinom(length(iyw), denom, prevalence)

  d <- data.table::data.table(
    indicator_tag = "fyrtarn_influensa_a_b", location_code = "norge",
    age = "total", sex = "total",
    isoyearweek_reference = iyw, reporting_date = monday,   # delay day 0
    numerator = num, denominator = denom)

  tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator_tag", "location_code", "age", "sex"))
  ens <- nowcast_delay_ecdf_v1(
    tri, max_delay_days = 28, n_sim = 50, denominator_col = "denominator")
  expect_true(all(c("numerator_nowcasted", "denominator_nowcasted") %in% names(ens$draws)))

  ens <- ens_add_rate(ens, "numerator_nowcasted", "denominator_nowcasted", per = 100)
  rate_key <- csfmt_var("numerator_nowcasted", denom = "denominator_nowcasted", per = 100)
  expect_true(rate_key %in% names(ens$draws))

  ens <- mem_thresholds_v1(ens, measure = rate_key)
  expect_true(any(!is.na(ens$data$mem_preepidemic)))      # thresholds fit on the % positive

  out <- ens_collapse(ens, probs = 0.5)
  expect_true(any(grepl(paste0(rate_key, ".*_status_prob_"), names(out))))   # alert levels
  expect_true(rate_key %in% sub("_q50x0$", "", grep(paste0("^", rate_key, "_q50x0$"),
                                                    names(out), value = TRUE)))
})
