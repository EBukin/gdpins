# gdpins 0.0.1.0

## New features

* The `sf` ⇄ parquet geometry encoding gained a **swappable WKT engine**,
  selectable per call or session-wide (#12).
  - `"wk"` (new **default**) uses the wk package: ~20× faster geometry writes
    than `sf` and full-precision.
  - `"sf"` remains available as a dependency-light fallback.
  - Choose it with the `engine` argument on `gdpins_sf_to_parquet()` /
    `gdpins_parquet_to_sf()`, the `wkt_engine` argument on `gdpins_pin_write()`,
    `gdpins_pin_read()`, `gdpins_raw_put_object()` and `gdpins_raw_get()`, or
    the `gdpins.wkt_engine` option (`options(gdpins.wkt_engine = "sf")`).
  - The two engines are read-compatible: WKT written by one reads back correctly
    with the other, so switching never requires re-encoding stored data.
* `wk` is now an `Imports` dependency (it backs the default engine).

## Bug fixes

* **Geometry precision.** The previous encoder called `sf::st_as_text()` at its
  default `getOption("digits")` (7 significant figures), which silently rounded
  projected coordinates (e.g. UTM 32643 metres) by up to ~0.5 m on write. Both
  engines are now full-precision — the `"wk"` engine by construction and the
  `"sf"` engine via `digits = 15`.

## Internal

* Added `tests/testthat/test-benchmark-wkt.R`, a skip-by-default benchmark
  (`GDPINS_BENCH_WKT=true`) comparing the sf / wk / lwgeom WKT engines across
  polygon and multipolygon workloads.
