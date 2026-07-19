# Package-level setup: register default options on load.

.onLoad <- function(libname, pkgname) {
  op       <- options()
  op_gdpins <- list(
    # Default WKT engine for sf <-> parquet geometry encoding. One of "wk"
    # (fast, full precision) or "sf" (fallback). See ?`io-formats`.
    gdpins.wkt_engine = "wk",

    # Default parquet (de)serialisation engine. One of "arrow" (default) or
    # "nanoparquet". arrow is the default because nanoparquet's reader can
    # allocate tens of GB on files with a few large (~MB) string cells, e.g.
    # WKT geometry columns. See ?`io-formats`.
    gdpins.parquet_engine = "arrow",

    # Default for gdpins_init_board(lazy=): defer Drive work and the sync
    # check until a board is first used. See ?`lazy-boards`.
    gdpins.lazy_boards = TRUE
  )
  to_set <- !(names(op_gdpins) %in% names(op))
  if (any(to_set)) options(op_gdpins[to_set])
  invisible()
}
