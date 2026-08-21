# "." is data.table's alias for list(), as in d[, .(x = ...)]. R CMD check reads
# it as an undefined function, and no local binding fixes that, so it is declared
# here. Every other NSE name is declared as NULL at the top of the one function
# that uses it, which keeps the declaration next to the code and stops a
# package-wide list from masking a genuine typo elsewhere.
utils::globalVariables(".")
