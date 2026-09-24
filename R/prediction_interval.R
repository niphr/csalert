#' Prediction interval for new data from a fitted model
#'
#' Internal: the deprecated `csfmt_rts_data_v1` method of [short_term_trend()] uses
#' it for its forecast.
#' @param object A fitted model.
#' @param newdata A data.frame of covariates.
#' @param alpha The two-sided significance level.
#' @param z The normal quantile. When given, it replaces `alpha`: `z = 1.96`
#'   equals `alpha = 0.05`.
#' @param ... Passed to the method.
#' @return A `data.table` with one row per row of `newdata`: `lower`, `point` and
#'   `upper`, on the response scale.
#' @keywords internal
prediction_interval <- function(object, newdata, alpha = 0.05, z = NULL, ...) {
  UseMethod("prediction_interval", object)
}


#' Prediction interval for new data from a Poisson or quasi-Poisson glm
#'
#' Internal. It combines the dispersion of the fit with the standard error of the
#' fitted mean, on the power scale that `skewness_transform` names.
#' @param object A `glm` of family `poisson` or `quasipoisson`.
#' @param newdata A data.frame of covariates.
#' @param alpha The two-sided significance level.
#' @param z The normal quantile. When given, it replaces `alpha`.
#' @param skewness_transform The power scale: `"none"`, `"1/2"` or `"2/3"`.
#' @param ... Not used, but the generic has it.
#' @return A `data.table` with one row per row of `newdata`: `lower`, `point` and
#'   `upper`, on the response scale. All three are `NA_real_` when any step gives
#'   a warning or an error.
#' @keywords internal
#' @method prediction_interval glm
#' @export
prediction_interval.glm <- function(
  object,
  newdata,
  alpha = 0.05,
  z = NULL,
  skewness_transform = "none",
  ...
) {
  stopifnot(object$family$family %in% c("poisson", "quasipoisson"))
  stopifnot(skewness_transform %in% c("none", "1/2", "2/3"))

  return(tryCatch(
    {
      pred <- stats::predict(object, newdata, type = "response", se.fit = TRUE)

      mu0 <- pred$fit
      phi <- summary(object)$dispersion

      tau <- phi + (pred$se.fit^2) / mu0
      switch(
        skewness_transform,
        none = {
          se <- sqrt(mu0 * tau)
          exponent <- 1
        },
        `1/2` = {
          se <- sqrt(1 / 4 * tau)
          exponent <- 1 / 2
        },
        `2/3` = {
          se <- sqrt(4 / 9 * mu0^(1 / 3) * tau)
          exponent <- 2 / 3
        },
        {
          stop("No proper exponent in prediction_interval.glm", call. = FALSE)
        }
      )

      if (is.null(z)) {
        z <- stats::qnorm(1 - alpha / 2)
      }
      lower <- (mu0^exponent - z * se)^(1 / exponent)
      upper <- (mu0^exponent + z * se)^(1 / exponent)

      return(
        data.table(
          lower = lower,
          point = mu0,
          upper = upper
        )
      )
    },
    warning = function(cond) {
      return(
        data.table(
          lower = rep(NA_real_, nrow(newdata)),
          point = rep(NA_real_, nrow(newdata)),
          upper = rep(NA_real_, nrow(newdata))
        )
      )
    },
    error = function(cond) {
      return(
        data.table(
          lower = rep(NA_real_, nrow(newdata)),
          point = rep(NA_real_, nrow(newdata)),
          upper = rep(NA_real_, nrow(newdata))
        )
      )
    }
  ))
}
