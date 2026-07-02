# nowcast_quasipoisson_v1: a DISCRIMINATIVE (regression) nowcast -- predict each
# week's eventual TOTAL directly from the counts reported so far, rather than
# modelling every triangle cell.
#
# For each horizon h (weeks a reference week has been observed) fit, on the SETTLED
# weeks, a quasipoisson regression with identity link and no intercept:
#
#     total  ~  b0 * n[delay 0] + b1 * n[delay 1] + ... + bh * n[delay h]
#
# i.e. "each case reported at delay d implies, on average, b_d cases in total."
# There is NO per-week magnitude parameter (the thing that made the chain-ladder
# noisy for exactly the recent weeks); the b's are shared and learned from many
# complete weeks, then applied to the incomplete weeks at that horizon. Draws come
# from the fit's prediction uncertainty (parameter) + a dispersion-matched negbin
# (observation) -> honestly dispersed. delay_window keeps the training weeks recent
# so the mapping tracks a drifting regime. Any fit issue leaves that horizon's
# weeks at their observed total (never errors).

# Complete a reference x delay matrix into n_sim totals via per-horizon regression.
.glm_complete <- function(mat, refs, as_of, max_delay, n_sim, delay_window) {
  weeks <- cstime::dates_by_isoyearweek$isoyearweek
  as_of_i <- match(as_of, weeks); ref_i <- match(refs, weeks)
  age <- as_of_i - ref_i                                  # weeks observed so far
  obs_total <- rowSums(mat)
  draws <- matrix(obs_total, length(refs), n_sim)         # settled weeks = observed
  settled <- age >= (max_delay - 1L)
  # train on recent settled weeks so the partial->total mapping tracks drift
  train <- which(settled & (if (is.null(delay_window)) TRUE else age < delay_window + max_delay))
  if (length(train) < 3L) return(draws)
  y_train <- obs_total[train]

  # one regression per number of weeks OBSERVED (1-based): weeks_observed w means
  # the reference week is age w-1, so delays 0..w-1 are in. (age 0 = the current
  # week with its delay-0 reports = 1 week observed.)
  ages <- sort(unique(age[!settled & age >= 0L & age < (max_delay - 1L)]))
  for (h in ages) {
    w <- h + 1L                                           # weeks observed
    cols <- seq_len(w)                                    # observed delays 0..w-1 -> matrix cols
    tgt  <- which(!settled & age == h)
    if (!length(tgt)) next
    Xtr <- mat[train, cols, drop = FALSE]
    df  <- data.frame(y = y_train, Xtr); names(df) <- c("y", paste0("d", cols))
    form <- stats::as.formula(paste("y ~", paste(paste0("d", cols), collapse = " + ")))  # + intercept
    s0  <- sum(y_train) / max(sum(Xtr), 1)                # overall inflation, a stable start
    fit <- tryCatch(stats::glm(form, family = stats::quasipoisson(link = "identity"),
                               data = df, start = c(0, rep(s0, length(cols)))),
                    error = function(e) NULL)
    if (is.null(fit) || anyNA(stats::coef(fit))) next
    Xnew <- as.data.frame(mat[tgt, cols, drop = FALSE]); names(Xnew) <- paste0("d", cols)
    pr <- tryCatch(stats::predict(fit, newdata = Xnew, type = "response", se.fit = TRUE),
                   error = function(e) NULL)
    if (is.null(pr)) next
    phi <- max(summary(fit)$dispersion, 1)
    for (ti in seq_along(tgt)) {
      mu <- pmax(stats::rnorm(n_sim, pr$fit[ti], pr$se.fit[ti]), 1e-6)   # parameter uncertainty
      size <- if (phi > 1) mu / (phi - 1) else Inf
      cnt <- stats::rnbinom(n_sim, size = size, mu = mu)                 # observation + overdispersion
      cnt[!is.finite(cnt)] <- obs_total[tgt[ti]]
      draws[tgt[ti], ] <- pmax(cnt, obs_total[tgt[ti]])                  # nowcast >= observed
    }
  }
  draws
}

#' Nowcast a reporting triangle into an ensemble (quasipoisson reporting regression)
#'
#' A discriminative (regression) nowcast engine: for each horizon it
#' regresses the settled total on the counts reported so far
#' (`total ~ n[delay 0] + n[delay 1] + ...`, quasipoisson/identity, no intercept)
#' and completes the incomplete weeks by simulating from that fit -- parameter
#' uncertainty plus a dispersion-matched negbin. No per-week magnitude parameter,
#' so it is robust for the recent weeks and honestly dispersed. Shares the contract
#' `f(reporting_triangle, ...) -> csfmt_ensemble_v3`.
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
#' @param delay_window Train on only settled weeks within roughly this many weeks
#'   (tracks a drifting regime). Default 26; `NULL` uses all settled weeks.
#' @returns A `csfmt_ensemble_v3` with one row per reference week and an
#'   `n_sim`-column draw matrix of the nowcasted total per week (settled weeks
#'   degenerate at their observed total; incomplete weeks carry the regression's
#'   parameter + dispersion uncertainty). A second measure is added when
#'   `denominator_col` is given.
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
