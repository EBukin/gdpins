# test-as-sf.R — tests for gdpins_as_sf() (R/io-formats.R)
#
# Covers the autodetecting WKT -> sf converter: column autodetection, EPSG
# inference (standard silent / non-standard message / default warning), explicit
# overrides, engine parity, and the guard/error paths.

# max abs coordinate deviation between two sf/sfc objects (same feature order)
as_max_dev <- function(a, b) {
  ca <- sf::st_coordinates(a)[, c("X", "Y")]
  cb <- sf::st_coordinates(b)[, c("X", "Y")]
  max(abs(ca - cb))
}

# ── column + EPSG autodetection: standard __epsg__ suffix ─────────────────────

test_that("standard __epsg__ column autodetects silently and restores sf", {
  x   <- fx_sf_single()                        # EPSG 4326, column "geometry"
  enc <- gdpins_sf_to_parquet(x)               # -> geometry__4326__

  expect_silent(got <- gdpins_as_sf(enc))
  expect_s3_class(got, "sf")
  expect_equal(sf::st_crs(got)$epsg, 4326L)
  expect_true("geometry" %in% names(got))       # standard suffix stripped
  expect_false(any(grepl("__\\d+__$", names(got))))
  expect_lt(as_max_dev(got, x), 1e-6)
})

# ── EPSG inference: non-standard digit run emits a message ────────────────────

test_that("non-standard column name infers EPSG from digits with a message", {
  df <- tibble::tibble(geom_3857 = "POINT (0 0)")

  expect_message(got <- gdpins_as_sf(df), "non-standard")
  expect_s3_class(got, "sf")
  expect_equal(sf::st_crs(got)$epsg, 3857L)
  expect_true("geom_3857" %in% names(got))       # non-standard name kept as-is
})

# ── EPSG inference: no digits -> default_epsg + warning ───────────────────────

test_that("digitless column name falls back to default_epsg with a warning", {
  df <- tibble::tibble(geom = "POINT (0 0)")

  expect_warning(got <- gdpins_as_sf(df), "assuming EPSG")
  expect_equal(sf::st_crs(got)$epsg, 4326L)

  # default_epsg is honoured
  expect_warning(got2 <- gdpins_as_sf(df, default_epsg = 3857L))
  expect_equal(sf::st_crs(got2)$epsg, 3857L)
})

# ── explicit epsg wins and silences inference ─────────────────────────────────

test_that("explicit epsg overrides the name and is silent", {
  df <- tibble::tibble(geom_9999 = "POINT (0 0)")   # digits would infer 9999
  expect_silent(got <- gdpins_as_sf(df, epsg = 4326))
  expect_equal(sf::st_crs(got)$epsg, 4326L)
})

test_that("invalid epsg is rejected", {
  df <- tibble::tibble(geom = "POINT (0 0)")
  expect_error(gdpins_as_sf(df, epsg = c(1L, 2L)), "single EPSG")
  expect_error(gdpins_as_sf(df, epsg = "abc"), "single EPSG")
})

# ── column selection among multiple candidates ────────────────────────────────

test_that("explicit column selects among multiple candidates", {
  x   <- fx_sf_multi_crs()                     # geom_wgs (4326), geom_web (3857)
  enc <- gdpins_sf_to_parquet(x)               # two __epsg__ columns

  got <- gdpins_as_sf(enc, column = "geom_wgs__4326__")
  expect_s3_class(got, "sf")
  expect_equal(sf::st_crs(got)$epsg, 4326L)
})

test_that("multiple candidates without column is an error", {
  x   <- fx_sf_multi_crs()
  enc <- gdpins_sf_to_parquet(x)
  expect_error(gdpins_as_sf(enc), "[Mm]ultiple")
})

test_that("zero candidates warns and returns the data unchanged", {
  df <- tibble::tibble(id = 1:3, value = c("a", "b", "c"))
  expect_warning(got <- gdpins_as_sf(df), "No WKT geometry column")
  expect_false(inherits(got, "sf"))
  expect_identical(got, df)
})

test_that("named-but-absent column is an error", {
  df <- tibble::tibble(geom = "POINT (0 0)")
  expect_error(gdpins_as_sf(df, column = "nope"), "not found")
})

# ── guard: character column that is not WKT ───────────────────────────────────

test_that("non-WKT geometry column is a hard error", {
  df <- tibble::tibble(geom__4326__ = c("not wkt", "still not"))
  expect_error(gdpins_as_sf(df), "valid WKT")
})

# ── already-sfc column short-circuits ─────────────────────────────────────────

test_that("an already-sf input is returned as sf", {
  x   <- fx_sf_single()
  got <- gdpins_as_sf(x, column = "geometry")
  expect_s3_class(got, "sf")
  expect_equal(sf::st_crs(got), sf::st_crs(x))
})

# ── engine parity: wk and sf parse identically ────────────────────────────────

test_that("wk and sf engines parse the same geometry", {
  x   <- fx_sf_poly_utm()                      # projected, sub-metre coords
  enc <- gdpins_sf_to_parquet(x, engine = "sf")

  got_wk <- gdpins_as_sf(enc, engine = "wk")
  got_sf <- gdpins_as_sf(enc, engine = "sf")
  expect_lt(as_max_dev(got_wk, x), 1e-6)
  expect_lt(as_max_dev(got_sf, x), 1e-6)
  expect_lt(as_max_dev(got_wk, got_sf), 1e-6)
})

# ── round-trip: encode then gdpins_as_sf reproduces geometry ──────────────────

test_that("sf_to_parquet -> gdpins_as_sf round-trips within precision", {
  for (fx in list(fx_sf_single(), fx_sf_poly_utm(), fx_sf_non4326())) {
    enc <- gdpins_sf_to_parquet(fx)
    got <- gdpins_as_sf(enc)
    expect_lt(as_max_dev(got, fx), 1e-6)
    expect_equal(sf::st_crs(got), sf::st_crs(fx))
  }
})
