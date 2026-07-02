# Self-contained weekly csfmt_rts_data_v1 skeleton for tests. Built from scratch
# (not a bundled dataset) so the suite does not depend on a particular cstidy
# data version. Tests add their own numerator column.
gen_weekly_skeleton <- function(isoyears, location = "norge") {
  cstidy::csfmt_rts_data_v1(data.table::data.table(
    granularity_time = "isoyearweek",
    location_code = location,
    isoyearweek = cstime::dates_by_isoyearweek[isoyear %in% isoyears]$isoyearweek,
    age = "total",
    sex = "total",
    border = 2020
  ))
}
