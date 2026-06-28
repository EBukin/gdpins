# test-io-formats.R — tests for R/io-formats.R
# Covers: gdpins_sf_to_parquet, gdpins_parquet_to_sf, gdpins_detect_format
# Uses Phase-0 fixtures: fx_plain_tbl, fx_list_col_tbl, fx_nested_tbl,
#   fx_sf_single, fx_sf_multi_crs, fx_sf_non4326


# ── gdpins_sf_to_parquet ──────────────────────────────────────────────────────

test_that("sf_to_parquet returns tibble, not sf", {
  result <- gdpins_sf_to_parquet(fx_sf_single())
  expect_s3_class(result, "tbl_df")
  expect_false(inherits(result, "sf"))
})

test_that("sf_to_parquet encodes single geometry col as WKT with EPSG 4326", {
  result <- gdpins_sf_to_parquet(fx_sf_single())
  # Original 'geometry' column should become 'geometry__4326__'
  expect_true("geometry__4326__" %in% names(result))
  expect_false("geometry" %in% names(result))
  # Values should be WKT strings starting with POINT
  expect_true(all(grepl("^POINT", result[["geometry__4326__"]])))
})

test_that("sf_to_parquet preserves non-geometry columns exactly", {
  input  <- fx_sf_single()
  result <- gdpins_sf_to_parquet(input)
  expect_equal(result$id,    input$id)
  expect_equal(result$label, input$label)
})

test_that("sf_to_parquet handles non-4326 CRS (EPSG 3857)", {
  result <- gdpins_sf_to_parquet(fx_sf_non4326())
  expect_true("geometry__3857__" %in% names(result))
  expect_false("geometry" %in% names(result))
  expect_type(result[["geometry__3857__"]], "character")
})

test_that("sf_to_parquet handles multi-geometry sf with differing CRS per col", {
  result <- gdpins_sf_to_parquet(fx_sf_multi_crs())
  expect_true("geom_wgs__4326__" %in% names(result))
  expect_true("geom_web__3857__" %in% names(result))
  expect_false("geom_wgs" %in% names(result))
  expect_false("geom_web" %in% names(result))
  # Both columns are plain character WKT
  expect_type(result[["geom_wgs__4326__"]], "character")
  expect_type(result[["geom_web__3857__"]], "character")
})

test_that("sf_to_parquet detects sfc by class not by column name", {
  # Build an sf with a column named 'centroid' (not 'geometry')
  pts <- sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(c(3, 4)), crs = 4326)
  input <- sf::st_sf(id = 1:2, centroid = pts)
  result <- gdpins_sf_to_parquet(input)
  expect_true("centroid__4326__" %in% names(result))
  expect_false("centroid" %in% names(result))
})

test_that("sf_to_parquet errors informatively when CRS has no EPSG", {
  pts <- sf::st_sfc(sf::st_point(c(1, 2)), crs = sf::st_crs(NA))
  input <- sf::st_sf(id = 1L, geom = pts)
  expect_error(
    gdpins_sf_to_parquet(input),
    class = "rlang_error"
  )
})

test_that("sf_to_parquet on plain tibble returns tibble unchanged (no sfc cols)", {
  tbl    <- fx_plain_tbl()
  result <- gdpins_sf_to_parquet(tbl)
  expect_s3_class(result, "tbl_df")
  expect_equal(names(result), names(tbl))
})


# ── gdpins_parquet_to_sf ──────────────────────────────────────────────────────

test_that("parquet_to_sf restores sf from single-geometry encoded tibble", {
  encoded <- gdpins_sf_to_parquet(fx_sf_single())
  result  <- gdpins_parquet_to_sf(encoded)
  expect_s3_class(result, "sf")
  expect_true("geometry" %in% names(result))
  expect_false("geometry__4326__" %in% names(result))
})

test_that("sf -> parquet -> sf round-trip is identity for EPSG 4326", {
  original <- fx_sf_single()
  result   <- gdpins_parquet_to_sf(gdpins_sf_to_parquet(original))

  # Geometry values identical
  expect_equal(
    sf::st_as_text(sf::st_geometry(result)),
    sf::st_as_text(sf::st_geometry(original))
  )
  # CRS preserved
  expect_equal(sf::st_crs(result), sf::st_crs(original))
  # Non-geometry columns identical
  expect_equal(result$id,    original$id)
  expect_equal(result$label, original$label)
})

test_that("sf -> parquet -> sf round-trip is identity for EPSG 3857", {
  original <- fx_sf_non4326()
  result   <- gdpins_parquet_to_sf(gdpins_sf_to_parquet(original))

  expect_equal(
    sf::st_as_text(sf::st_geometry(result)),
    sf::st_as_text(sf::st_geometry(original))
  )
  expect_equal(sf::st_crs(result)$epsg, 3857L)
})

test_that("sf -> parquet -> sf round-trip restores multi-CRS with each CRS correct", {
  original <- fx_sf_multi_crs()
  encoded  <- gdpins_sf_to_parquet(original)
  result   <- gdpins_parquet_to_sf(encoded)

  expect_s3_class(result, "sf")
  # Both geometry columns present with base names
  expect_true("geom_wgs" %in% names(result))
  expect_true("geom_web" %in% names(result))
  # CRS per column
  expect_equal(sf::st_crs(result[["geom_wgs"]])$epsg, 4326L)
  expect_equal(sf::st_crs(result[["geom_web"]])$epsg, 3857L)
  # Geometry values match original
  expect_equal(
    sf::st_as_text(result[["geom_wgs"]]),
    sf::st_as_text(original[["geom_wgs"]])
  )
  expect_equal(
    sf::st_as_text(result[["geom_web"]]),
    sf::st_as_text(original[["geom_web"]])
  )
})

test_that("parquet_to_sf returns input unchanged when no __epsg__ columns", {
  tbl    <- fx_plain_tbl()
  result <- gdpins_parquet_to_sf(tbl)
  expect_identical(result, tbl)
})

test_that("parquet_to_sf guard: chr col named like __epsg__ but NOT valid WKT is left unchanged", {
  # A plain character column named "foo__1234__" whose values are not WKT
  tbl <- tibble::tibble(
    id           = 1:3,
    foo__1234__  = c("not wkt at all", "also not wkt", "definitely not wkt")
  )
  result <- gdpins_parquet_to_sf(tbl)
  # Should not be converted to sf
  expect_false(inherits(result, "sf"))
  # Column should still be named foo__1234__ (NOT renamed to foo)
  expect_true("foo__1234__" %in% names(result))
  expect_false("foo" %in% names(result))
  # Values unchanged
  expect_equal(result[["foo__1234__"]], tbl[["foo__1234__"]])
})

test_that("parquet_to_sf guard: mixed valid + invalid WKT cols — only valid ones converted", {
  pts <- sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(c(3, 4)), crs = 4326)
  tbl <- tibble::tibble(
    id          = 1:2,
    geom__4326__ = sf::st_as_text(pts),      # valid WKT
    junk__9999__ = c("not wkt", "also bad")  # invalid WKT (also unlikely EPSG)
  )
  result <- gdpins_parquet_to_sf(tbl)
  # geom col should be converted
  expect_true("geom" %in% names(result))
  # junk col: invalid WKT → stays unchanged with original name
  expect_true("junk__9999__" %in% names(result))
  expect_false("junk" %in% names(result))
})


# ── gdpins_detect_format ──────────────────────────────────────────────────────

test_that("detect_format returns 'arrow' for plain tibble", {
  expect_equal(gdpins_detect_format(fx_plain_tbl()), "arrow")
})

test_that("detect_format returns 'arrow' for plain data.frame", {
  expect_equal(gdpins_detect_format(as.data.frame(fx_plain_tbl())), "arrow")
})

test_that("detect_format returns 'arrow' for sf object (sfc cols are ok)", {
  expect_equal(gdpins_detect_format(fx_sf_single()), "arrow")
  expect_equal(gdpins_detect_format(fx_sf_multi_crs()), "arrow")
  expect_equal(gdpins_detect_format(fx_sf_non4326()), "arrow")
})

test_that("detect_format returns 'rds' for tibble with list-column", {
  expect_equal(gdpins_detect_format(fx_list_col_tbl()), "rds")
})

test_that("detect_format returns 'rds' for nested tibble", {
  expect_equal(gdpins_detect_format(fx_nested_tbl()), "rds")
})

test_that("detect_format returns 'rds' for bare list", {
  expect_equal(gdpins_detect_format(list(a = 1, b = 2)), "rds")
})

test_that("detect_format returns 'rds' for non-data-frame object", {
  expect_equal(gdpins_detect_format(1:10), "rds")
  expect_equal(gdpins_detect_format(matrix(1:4, 2, 2)), "rds")
  expect_equal(gdpins_detect_format("a string"), "rds")
})

test_that("detect_format 'arrow' for tibble with ONLY sfc list-cols (sf is fine)", {
  # sf data frame: list-cols are sfc, so arrow
  sf_obj <- fx_sf_single()
  expect_equal(gdpins_detect_format(sf_obj), "arrow")
})

test_that("detect_format 'rds' for tibble with mixed sfc and non-sfc list-cols", {
  pts <- sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(c(3, 4)), crs = 4326)
  tbl <- tibble::tibble(
    id   = 1:2,
    geom = pts,                          # sfc — ok
    data = list(list(x = 1), list(x = 2)) # non-sfc list-col — forces rds
  )
  # It's not a proper sf but has mixed list cols
  expect_equal(gdpins_detect_format(tbl), "rds")
})
