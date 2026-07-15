# Changelog

## gdpins 0.0.1.0

### New features

- The `sf` ⇄ parquet geometry encoding gained a **swappable WKT
  engine**, selectable per call or session-wide (#12).
  - `"wk"` (new **default**) uses the wk package: ~20× faster geometry
    writes than `sf` and full-precision.
  - `"sf"` remains available as a dependency-light fallback.
  - Choose it with the `engine` argument on
    [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
    /
    [`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md),
    the `wkt_engine` argument on
    [`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
    [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
    [`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md)
    and
    [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
    or the `gdpins.wkt_engine` option
    (`options(gdpins.wkt_engine = "sf")`).
  - The two engines are read-compatible: WKT written by one reads back
    correctly with the other, so switching never requires re-encoding
    stored data.
- `wk` is now an `Imports` dependency (it backs the default engine).

### Bug fixes

- **Geometry precision.** The previous encoder called
  [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
  at its default `getOption("digits")` (7 significant figures), which
  silently rounded projected coordinates (e.g. UTM 32643 metres) by up
  to ~0.5 m on write. Both engines are now full-precision — the `"wk"`
  engine by construction and the `"sf"` engine via `digits = 15`.

### Internal

- Added `tests/testthat/test-benchmark-wkt.R`, a skip-by-default
  benchmark (`GDPINS_BENCH_WKT=true`) comparing the sf / wk / lwgeom WKT
  engines across polygon and multipolygon workloads.
