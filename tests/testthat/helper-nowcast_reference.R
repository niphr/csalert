# The reference implementation of nowcast_delay_ecdf_v1(), copied from
# luftveisovervaking_trend, R_nowcast_comparison_v01/nowcast_candidates.R:
# .series(), .ensemble() and nowcast_ecdf_variant(). The tests compare the
# engine's draw quantiles with it.
#
# Changes from the source, and nothing else:
# - every name has a `ref_` prefix, so it cannot mask a csalert internal inside
#   the test environment;
# - isoyearweek_week_start() is called as csalert:::isoyearweek_week_start();
# - the observed total is rowSums(m$mat) + m$late, as in the engine. A report
#   past the horizon stays in `original` and in the draws of a settled week;
# - the `robust` and `drop_outages` branches are removed, so only the empirical
#   interval of the default engine remains.

.ref_series <- function(x, max_delay_days) {
  m <- csalert::reporting_triangle_matrix(
    x,
    max_delay_days,
    value_col = attr(x, "value_col")
  )[[1]]
  m$age_days <- as.integer(
    attr(x, "as_of") - csalert:::isoyearweek_week_start(m$reference)
  )
  m
}

.ref_ensemble <- function(x, m, draws) {
  id_cols <- attr(x, "id_cols")
  dt <- data.table::as.data.table(x)
  data <- unique(dt[, id_cols, with = FALSE])[rep(1L, length(m$reference))]
  data[, `:=`(isoyearweek = m$reference, original = rowSums(m$mat) + m$late)]
  csalert::csfmt_ensemble_v3(
    data,
    id_cols = id_cols,
    time_col = "isoyearweek",
    draws = stats::setNames(
      list(draws),
      csalert::csfmt_var(attr(x, "value_col"), role = "nowcasted")
    )
  )
}

ref_nowcast_ecdf_variant <- function(
  x,
  max_delay_days,
  delay_window = 26L,
  n_sim = 1000L
) {
  m <- .ref_series(x, max_delay_days)
  md <- max_delay_days
  obs_total <- rowSums(m$mat) + m$late
  draws <- matrix(obs_total, length(m$reference), n_sim)
  settled <- m$age_days >= md - 1L
  pool <- which(settled & m$age_days < delay_window * 7L + md)
  if (length(pool) < 3L) {
    return(.ref_ensemble(x, m, draws))
  }

  for (i in which(!settled & m$age_days >= 0L)) {
    d <- m$age_days[i]
    cols <- seq_len(d + 1L)
    O <- sum(m$mat[i, cols])
    Os <- rowSums(m$mat[pool, cols, drop = FALSE])
    Ts <- rowSums(m$mat[pool, , drop = FALSE])
    ok <- Os > 0
    if (sum(ok) < 3L || O <= 0) {
      next
    }
    r <- Ts[ok] / Os[ok]
    v <- O * stats::quantile(r, (seq_len(n_sim) - 1) / (n_sim - 1), names = FALSE)
    draws[i, ] <- sample(pmax(v, obs_total[i]))
  }
  .ref_ensemble(x, m, draws)
}
