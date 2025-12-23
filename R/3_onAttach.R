#' @import data.table ggplot2
#' @importFrom magrittr %>%
.onAttach <- function(libname, pkgname) {
    version <- tryCatch(
      utils::packageDescription("csalert", fields = "Version"),
      warning = function(w){
        1
      }
    )

  packageStartupMessage(paste0(
    "csalert ",
    version,
    "\n",
    "https://niphr.github.io/csalert/"
  ))
}
