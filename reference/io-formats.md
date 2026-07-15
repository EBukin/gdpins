# I/O format detection and geospatial encoding

Functions for converting between R objects and storage formats, with
special handling for `sf` geospatial objects using a WKT + column-name
CRS encoding.

## WKT engine

The geometry \<-\> WKT text conversion can be performed by one of two
engines, selected with the `engine` argument (or, package-wide, the
`gdpins.wkt_engine` option):

- `"wk"` (default) — uses
  [`wk::as_wkt()`](https://paleolimbot.github.io/wk/reference/wkt.html)
  to write and routes reads through
  [`wk::wkt()`](https://paleolimbot.github.io/wk/reference/wkt.html)
  into
  [`sf::st_as_sfc()`](https://r-spatial.github.io/sf/reference/st_as_sfc.html).
  About 20x faster to write than `"sf"` and always full-precision.

- `"sf"` — uses
  [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
  (with `digits = 15`, so it is full-precision) to write and
  [`sf::st_as_sfc()`](https://r-spatial.github.io/sf/reference/st_as_sfc.html)
  to read. Kept as a fallback so encoding never depends on a single
  engine.

Both engines are read-compatible: WKT written by one reads back
correctly with the other. The default can be changed globally with
`options(gdpins.wkt_engine = "sf")`.

Note:
[`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
defaults to `getOption("digits")` (7 significant figures), which
silently rounds projected coordinates (e.g. UTM metres) by up to ~0.5 m.
gdpins always pins `digits = 15` for the `"sf"` engine to avoid this;
the `"wk"` engine is full-precision by construction.
