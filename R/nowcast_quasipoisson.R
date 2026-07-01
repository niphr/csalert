# nowcast_quasipoisson_v1: chain-ladder nowcast via a (quasi)Poisson GLM on the
# reporting triangle, emitting posterior-predictive DRAWS (not an analytic
# interval).
#
# Fit  count[ref, delay] ~ factor(ref) + factor(delay)  (quasipoisson) on the
# observed cells of the recent window: the reference effect is the week's
# magnitude, the delay effect the reporting profile. Then complete each
# not-yet-fully-reported week by SIMULATING its missing cells -- draw the GLM
# coefficients from their sampling distribution (MVN, so the uncertainty is
# correlated across a week's cells), predict each missing cell's mean, and draw
# the count from a negative binomial matched to the estimated dispersion. Summing
# observed + simulated cells gives the completed-total draws.
#
# This propagates BOTH parameter and observation/overdispersion uncertainty and
# stays non-negative integer -- honestly dispersed by construction (unlike a
# plug-in), and no Farrington/normal-interval approximation is needed because the
# ensemble is simulated directly. Any fit/rank issue falls back to the observed
# totals (never errors). delay_window keeps the fit on the current regime, as in
# nowcast_survrtrunc_v1.

# Complete a reference x delay count matrix into n_sim totals via GLM simulation.
.glm_complete <- function(mat, refs, as_of, max_delay, n_sim, delay_window) {
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  as_of_i <- match(as_of, weeks); ref_i <- match(refs, weeks)
  nref <- length(refs)
  obs_total <- rowSums(mat)
  draws <- matrix(obs_total, nref, n_sim)                 # default: settled weeks = observed

  incomplete <- (as_of_i - ref_i) < (max_delay - 1L)      # still has unobservable cells
  in_win <- if (is.null(delay_window)) rep(TRUE, nref) else (as_of_i - ref_i) < delay_window
  fit_rows <- which(in_win)
  if (!any(incomplete & in_win) || length(fit_rows) < 2L) return(draws)

  grid <- data.table::CJ(ri = fit_rows, dj = seq_len(max_delay))
  grid[, `:=`(ref = factor(refs[ri]), delay = factor(dj),
              count = mat[cbind(ri, dj)],
              observed = (ref_i[ri] + (dj - 1L)) <= as_of_i)]
  if (data.table::uniqueN(grid[observed == TRUE]$delay) < 2L) return(draws)   # no delay signal

  fit <- tryCatch(stats::glm(count ~ ref + delay, family = stats::quasipoisson(),
                             data = grid[observed == TRUE]), error = function(e) NULL)
  if (is.null(fit)) return(draws)
  un <- grid[observed == FALSE & ri %in% which(incomplete)]
  if (!nrow(un)) return(draws)

  beta <- stats::coef(fit)
  if (anyNA(beta)) return(draws)                          # rank-deficient -> skip
  X <- tryCatch(stats::model.matrix(stats::delete.response(stats::terms(fit)),
                                    data = un, contrasts.arg = fit$contrasts),
                error = function(e) NULL)
  V <- tryCatch(stats::vcov(fit), error = function(e) NULL)
  if (is.null(X) || is.null(V)) return(draws)
  keep <- intersect(colnames(X), names(beta))
  if (!length(keep)) return(draws)
  X <- X[, keep, drop = FALSE]; b <- beta[keep]; V <- V[keep, keep, drop = FALSE]
  L <- tryCatch(chol(V), error = function(e) NULL); if (is.null(L)) return(draws)

  Z <- matrix(stats::rnorm(length(b) * n_sim), length(b), n_sim)
  beta_star <- b + t(L) %*% Z                             # p x n_sim (correlated draws)
  mu <- exp(pmin(X %*% beta_star, 700))                   # ncell x n_sim, overflow-guarded
  phi <- max(summary(fit)$dispersion, 1)
  size <- if (phi > 1) mu / (phi - 1) else matrix(Inf, nrow(mu), ncol(mu))
  cnt <- matrix(stats::rnbinom(length(mu), size = size, mu = mu), nrow(mu), ncol(mu))
  cnt[!is.finite(cnt)] <- 0

  add <- rowsum(cnt, un$ri)                               # (unique ri) x n_sim
  ri_add <- as.integer(rownames(add))
  draws[ri_add, ] <- obs_total[ri_add] + add
  draws
}

#' Nowcast a reporting triangle into an ensemble (quasipoisson chain-ladder GLM)
#'
#' A chain-ladder GLM alternative to [nowcast_survrtrunc_v1]: models the reporting
#' triangle counts as `count ~ factor(ref) + factor(delay)` (quasipoisson) and
#' completes recent weeks by simulating the missing cells (parameter + negbin
#' observation uncertainty), so its intervals are honestly dispersed. Shares the
#' contract `f(reporting_triangle, ...) -> csfmt_ensemble_v3`.
#' @param x A `csfmt_reporting_triangle_v3`.
#' @param ... Passed to methods.
#' @rdname nowcast_quasipoisson_v1
#' @export
nowcast_quasipoisson_v1 <- function(x, ...) UseMethod("nowcast_quasipoisson_v1")

#' @method nowcast_quasipoisson_v1 csfmt_reporting_triangle_v3
#' @rdname nowcast_quasipoisson_v1
#' @param max_delay Delay horizon in weeks.
#' @param n_sim Number of nowcast draws.
#' @param denominator_col Optional denominator column to nowcast alongside.
#' @param delay_window Fit on only the most recent `delay_window` reference weeks
#'   (tracks a drifting regime). Default 26; `NULL` uses all history.
#' @export
nowcast_quasipoisson_v1.csfmt_reporting_triangle_v3 <- function(x, max_delay, n_sim = 1000,
                                                denominator_col = NULL, delay_window = 26, ...) {
  id_cols <- attr(x, "id_cols"); val_col <- attr(x, "value_col"); as_of <- attr(x, "as_of")
  value_cols <- c(val_col, denominator_col)
  d_tri <- data.table::as.data.table(x)
  rts_num <- reporting_triangle_matrix(x, max_delay, value_col = val_col)
  series_ids <- names(rts_num)

  data_rows <- list()
  for (tsid in series_ids) {
    refs <- rts_num[[tsid]]$reference
    idvals <- unique(d_tri[time_series_id == tsid, id_cols, with = FALSE])[rep(1L, length(refs))]
    idvals[, isoyearweek := refs]; idvals[, original := rowSums(rts_num[[tsid]]$mat)]
    data_rows[[tsid]] <- idvals
  }
  data <- data.table::rbindlist(data_rows)

  draws <- list()
  for (vc in value_cols) {
    rts <- reporting_triangle_matrix(x, max_delay, value_col = vc)
    chunks <- lapply(series_ids, function(tsid)
      .glm_complete(rts[[tsid]]$mat, rts[[tsid]]$reference, as_of, max_delay, n_sim, delay_window))
    draws[[csfmt_var(vc, role = "nowcasted")]] <- do.call(rbind, chunks)
    if (!identical(vc, val_col)) {
      obs <- unlist(lapply(series_ids, function(tsid) rowSums(rts[[tsid]]$mat)))
      data[, (csfmt_var(vc, role = "observed")) := obs]
    }
  }
  csfmt_ensemble_v3(data, id_cols = id_cols, time_col = "isoyearweek", draws = draws)
}
