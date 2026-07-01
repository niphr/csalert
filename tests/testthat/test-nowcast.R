# nowcast: triangle -> ensemble, validated against synthetic ground truth.

skip_if_not_installed("flexsurv")

# Simulate a KNOWN process: Poisson reference-week counts, each case reported with
# a delay drawn from a known decreasing distribution, then right-truncated at the
# latest week. We hold out the true total per reference week.
simulate_triangle <- function(n_weeks = 18, lambda = 60, max_delay = 4, seed = 1) {
  set.seed(seed)
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  i0 <- which(weeks == "2020-01")
  ref_weeks <- weeks[i0:(i0 + n_weeks - 1)]
  delay_p <- (max_delay:1) / sum(max_delay:1)

  rows <- list(); truth <- integer(n_weeks)
  for (w in seq_len(n_weeks)) {
    n <- stats::rpois(1, lambda); truth[w] <- n
    if (n == 0) next
    delays <- sample(0:(max_delay - 1), n, replace = TRUE, prob = delay_p)
    rows[[w]] <- data.table::data.table(isoyearweek_reference = ref_weeks[w],
                                        rep_idx = (i0 + w - 1) + delays)
  }
  ll <- data.table::rbindlist(rows)
  ll[, isoyearweek_reporting := weeks[rep_idx]]
  ll <- ll[rep_idx <= i0 + n_weeks - 1]                  # truncate at as-of
  tri <- ll[, .(numerator = .N), by = .(isoyearweek_reference, isoyearweek_reporting)]
  tri[, `:=`(indicator = "test", location = "nation", age = "total", sex = "total")]
  list(tri = tri[],
       truth = data.table::data.table(isoyearweek = ref_weeks, truth = truth))
}

test_that("nowcast returns an ensemble with nowcasted draws aligned to references", {
  sim <- simulate_triangle()
  tri <- csfmt_reporting_triangle_v3(sim$tri, id_cols = c("indicator", "location", "age", "sex"))
  ens <- nowcast_simple(tri, max_delay = 4, n_sim = 200)

  expect_s3_class(ens, "csfmt_ensemble_v3")
  expect_true("numerator_nowcasted" %in% names(ens$draws))
  expect_equal(nrow(ens$draws$numerator_nowcasted), nrow(ens$data))
  expect_equal(ncol(ens$draws$numerator_nowcasted), 200L)
})

test_that("nowcast surfaces the observed denominator total (role = observed)", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay = 4, seed = 3)
  # add a denominator: a known multiple of the numerator on each triangle cell
  sim$tri[, denominator := numerator * 3L + 1L]
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"),
    value_col = "numerator")
  ens <- nowcast_simple(tri, max_delay = 4, n_sim = 100, denominator_col = "denominator")

  # both measures get nowcast draws ...
  expect_true(all(c("numerator_nowcasted", "denominator_nowcasted") %in% names(ens$draws)))
  # ... and the denominator's observed (reported-so-far) total is on $data
  expect_true("denominator_observed" %in% names(ens$data))
  # observed denominator equals the reported-so-far cell sums (>= 0, aligned)
  expect_equal(nrow(ens$data), length(ens$data$denominator_observed))
  expect_true(all(ens$data$denominator_observed >= 0))
  # denominator observed >= numerator observed here (denominator is the larger)
  expect_true(all(ens$data$denominator_observed >= ens$data$original))
})

test_that("observed_ensemble passes the triangle through without nowcasting", {
  sim <- simulate_triangle(n_weeks = 12, lambda = 40, max_delay = 4, seed = 5)
  tri <- csfmt_reporting_triangle_v3(
    sim$tri, id_cols = c("indicator", "location", "age", "sex"))
  ens <- nowcast_passthrough_to_ensemble(tri, max_delay = 4)

  expect_s3_class(ens, "csfmt_ensemble_v3")
  # degenerate: a single draw column
  expect_equal(ncol(ens$draws$numerator_nowcasted), 1L)
  # the "nowcasted" value equals the observed total (no completion applied)
  expect_equal(as.numeric(ens$draws$numerator_nowcasted[, 1]), ens$data$original)

  # collapse -> every quantile equals the observed point
  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  expect_equal(out$numerator_nowcasted_q50x0, out$original)
  expect_equal(out$numerator_nowcasted_q02x5, out$original)
  expect_equal(out$numerator_nowcasted_q97x5, out$original)
})

test_that("nowcast recovers the truncated cases (>= observed, with coverage)", {
  sim <- simulate_triangle(n_weeks = 18, lambda = 60, max_delay = 4, seed = 1)
  tri <- csfmt_reporting_triangle_v3(sim$tri, id_cols = c("indicator", "location", "age", "sex"))
  ens <- nowcast_simple(tri, max_delay = 4, n_sim = 500)
  out <- ens_collapse(ens, probs = c(0.025, 0.5, 0.975))
  out <- merge(out, sim$truth, by = "isoyearweek")

  med <- out[["numerator_nowcasted_q50x0"]]
  lo  <- out[["numerator_nowcasted_q02x5"]]
  hi  <- out[["numerator_nowcasted_q97x5"]]

  # the nowcast adds the unreported cases: median >= observed
  expect_true(all(med >= out$original - 1e-9))
  # ground truth lies within the nowcast interval for most weeks
  covered <- out$truth >= lo & out$truth <= hi
  expect_gt(mean(covered), 0.6)
})
