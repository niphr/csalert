# The reference implementation of the nowcast_delay_ecdf_v1() options, copied
# from luftveisovervaking_trend, R_nowcast_comparison_v01/nowcast_candidates.R:
# .series(), .ensemble(), .gap_len() and nowcast_ecdf_variant(). The tests
# compare the engine's draw quantiles with it.
#
# Changes from the source, and nothing else:
# - every name has a `ref_` prefix, so it cannot mask a csalert internal such as
#   .gap_len() inside the test environment;
# - isoyearweek_week_start() is called as csalert:::isoyearweek_week_start().
#
# Mapping: robust = TRUE is interval = "log_robust", and
# drop_outages = TRUE, gap_days = g is outage_gap_days = g.

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
  data[, `:=`(isoyearweek = m$reference, original = rowSums(m$mat))]
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

# Longest run of no-delivery dates in [from, to], per pair.
.ref_gap_len <- function(from, to, delivery_dates) {
  mapply(
    function(a, b) {
      if (b < a) {
        return(0L)
      }
      off <- !(seq(a, b, by = 1) %in% delivery_dates)
      r <- rle(off)
      max(c(0L, r$lengths[r$values]))
    },
    from,
    to
  )
}

ref_nowcast_ecdf_variant <- function(
  x,
  max_delay_days,
  robust = FALSE,
  drop_outages = FALSE,
  gap_days = 3L,
  delay_window = 26L,
  n_sim = 1000L
) {
  m <- .ref_series(x, max_delay_days)
  md <- max_delay_days
  obs_total <- rowSums(m$mat)
  draws <- matrix(obs_total, length(m$reference), n_sim)
  settled <- m$age_days >= md - 1L
  pool <- which(settled & m$age_days < delay_window * 7L + md)
  if (length(pool) < 3L) {
    return(.ref_ensemble(x, m, draws))
  }
  mon <- csalert:::isoyearweek_week_start(m$reference)
  tri <- data.table::as.data.table(x)
  delivery <- unique(tri[
    get(attr(x, "value_col")) > 0,
    get(attr(x, "reporting_col"))
  ])

  for (i in which(!settled & m$age_days >= 0L)) {
    d <- m$age_days[i]
    cols <- seq_len(d + 1L)
    O <- sum(m$mat[i, cols])
    p <- pool
    if (drop_outages) {
      target_gap <- .ref_gap_len(mon[i], mon[i] + d, delivery) >= gap_days
      if (!target_gap) {
        pool_gap <- .ref_gap_len(mon[p], mon[p] + d, delivery) >= gap_days
        if (sum(!pool_gap) >= 3L) p <- p[!pool_gap]
      }
    }
    Os <- rowSums(m$mat[p, cols, drop = FALSE])
    Ts <- rowSums(m$mat[p, , drop = FALSE])
    ok <- Os > 0
    if (sum(ok) < 3L || O <= 0) {
      next
    }
    r <- Ts[ok] / Os[ok]
    v <- if (robust) {
      lr <- log(r)
      O * exp(stats::median(lr) + stats::mad(lr) * stats::rnorm(n_sim))
    } else {
      O * stats::quantile(r, (seq_len(n_sim) - 1) / (n_sim - 1), names = FALSE)
    }
    draws[i, ] <- sample(pmax(v, obs_total[i]))
  }
  .ref_ensemble(x, m, draws)
}
