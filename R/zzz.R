# Package-level setup: register default options on load.

.onLoad <- function(libname, pkgname) {
  op       <- options()
  op_gdpins <- list(
    # Default WKT engine for sf <-> parquet geometry encoding. One of "wk"
    # (fast, full precision) or "sf" (fallback). See ?`io-formats`.
    gdpins.wkt_engine = "wk"
  )
  to_set <- !(names(op_gdpins) %in% names(op))
  if (any(to_set)) options(op_gdpins[to_set])
  invisible()
}
