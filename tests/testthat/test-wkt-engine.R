# test-wkt-engine.R — regression tests for the swappable WKT engine
#
# Covers R/io-formats.R (engine arg + .gdpins_wkt_engine resolver) and the
# wkt_engine pass-through in gdpins_pin_write/read and the raw connection.
#
# The point of these tests is that "wk" (default) and "sf" are fully
# interchangeable and precision-safe: geometry survives any write-engine /
# read-engine combination unchanged, on both geographic and projected CRS.

# max abs coordinate deviation between two sf/sfc objects (same feature order)
we_max_dev <- function(a, b) {
  ca <- sf::st_coordinates(a)[, c("X", "Y")]
  cb <- sf::st_coordinates(b)[, c("X", "Y")]
  max(abs(ca - cb))
}

we_fixtures <- function() {
  list(
    point_4326     = fx_sf_single(),
    poly_utm       = fx_sf_poly_utm(),
    multipoly_utm  = fx_sf_multipoly_utm(),
    non4326        = fx_sf_non4326()
  )
}

# ── engine resolver ───────────────────────────────────────────────────────────

test_that("default WKT engine is 'wk'", {
  withr::local_options(gdpins.wkt_engine = NULL)   # unset -> built-in default
  expect_equal(.gdpins_wkt_engine(NULL), "wk")
})

test_that("engine resolver honours explicit arg over option", {
  withr::local_options(gdpins.wkt_engine = "wk")
  expect_equal(.gdpins_wkt_engine("sf"), "sf")
  expect_equal(.gdpins_wkt_engine("wk"), "wk")
})

test_that("engine resolver honours the gdpins.wkt_engine option when arg is NULL", {
  withr::local_options(gdpins.wkt_engine = "sf")
  expect_equal(.gdpins_wkt_engine(NULL), "sf")
})

test_that("engine resolver rejects unknown engines informatively", {
  expect_error(.gdpins_wkt_engine("wkb"), class = "rlang_error")
  expect_error(.gdpins_wkt_engine("geos"), "wk.*sf|sf.*wk")
})

# ── both engines encode to the same schema ────────────────────────────────────

test_that("both engines produce identical column names and non-geometry data", {
  for (nm in names(we_fixtures())) {
    x <- we_fixtures()[[nm]]
    enc_wk <- gdpins_sf_to_parquet(x, engine = "wk")
    enc_sf <- gdpins_sf_to_parquet(x, engine = "sf")
    expect_identical(names(enc_wk), names(enc_sf), info = nm)
    # WKT columns are character in both
    geo_cols <- grep("__\\d{4,5}__$", names(enc_wk), value = TRUE)
    for (gc in geo_cols) {
      expect_type(enc_wk[[gc]], "character")
      expect_type(enc_sf[[gc]], "character")
    }
  }
})

# ── round-trip identity for every engine, on every fixture ────────────────────

test_that("write/read round-trip preserves geometry for both engines (all CRS)", {
  for (nm in names(we_fixtures())) {
    x <- we_fixtures()[[nm]]
    for (eng in c("wk", "sf")) {
      rt <- gdpins_parquet_to_sf(
        gdpins_sf_to_parquet(x, engine = eng),
        engine = eng
      )
      expect_s3_class(rt, "sf")
      expect_lt(we_max_dev(rt, x), 1e-6)                 # precision-safe
      expect_equal(sf::st_crs(rt), sf::st_crs(x), info = paste(nm, eng))
      expect_equal(rt$id, x$id, info = paste(nm, eng))
    }
  }
})

# ── cross-engine interchange: written by one, read by the other ───────────────

test_that("WKT written by either engine reads back correctly with the other", {
  for (nm in names(we_fixtures())) {
    x <- we_fixtures()[[nm]]
    enc_wk <- gdpins_sf_to_parquet(x, engine = "wk")
    enc_sf <- gdpins_sf_to_parquet(x, engine = "sf")

    combos <- list(
      c("wk", "wk"), c("wk", "sf"), c("sf", "wk"), c("sf", "sf")
    )
    for (cc in combos) {
      enc <- if (cc[[1]] == "wk") enc_wk else enc_sf
      rt  <- gdpins_parquet_to_sf(enc, engine = cc[[2]])
      expect_lt(
        we_max_dev(rt, x), 1e-6,
        label = sprintf("%s: write=%s read=%s", nm, cc[[1]], cc[[2]])
      )
    }
  }
})

# ── precision regression: sf engine must NOT reintroduce the digits=7 loss ─────

test_that("sf engine writes full precision on projected CRS (no digits=7 loss)", {
  x <- fx_sf_poly_utm()

  # gdpins' sf engine (digits = 15) is lossless ...
  rt_gdpins_sf <- gdpins_parquet_to_sf(
    gdpins_sf_to_parquet(x, engine = "sf"), engine = "sf"
  )
  expect_lt(we_max_dev(rt_gdpins_sf, x), 1e-6)

  # ... whereas a naive sf::st_as_text() at default digits loses >1 cm here,
  # which is exactly the bug this engine work fixes. (Guards the fix.)
  naive_txt <- sf::st_as_text(sf::st_geometry(x))          # default digits == 7
  naive_rt  <- sf::st_as_sfc(naive_txt, crs = sf::st_crs(x))
  expect_gt(we_max_dev(naive_rt, sf::st_geometry(x)), 1e-2)
})

# ── option flips the default engine used by the core functions ────────────────

test_that("gdpins.wkt_engine option flips the default engine (round-trip still ok)", {
  x <- fx_sf_poly_utm()
  withr::local_options(gdpins.wkt_engine = "sf")
  # engine = NULL -> resolves to the option ("sf")
  enc <- gdpins_sf_to_parquet(x, engine = NULL)
  rt  <- gdpins_parquet_to_sf(enc, engine = NULL)
  expect_lt(we_max_dev(rt, x), 1e-6)
})

# ── non-geometry guard still holds under the wk engine ────────────────────────

test_that("parquet_to_sf guard leaves invalid-WKT __epsg__ cols alone (both engines)", {
  tbl <- tibble::tibble(
    id          = 1:3,
    foo__1234__ = c("not wkt at all", "also not wkt", "definitely not wkt")
  )
  for (eng in c("wk", "sf")) {
    result <- gdpins_parquet_to_sf(tbl, engine = eng)
    expect_false(inherits(result, "sf"), info = eng)
    expect_true("foo__1234__" %in% names(result), info = eng)
    expect_equal(result[["foo__1234__"]], tbl[["foo__1234__"]], info = eng)
  }
})

# ── integration: pin_write/pin_read wkt_engine pass-through ────────────────────

test_that("pin_write/pin_read round-trip sf via wkt_engine (default + explicit)", {
  x <- fx_sf_poly_utm()

  for (eng in list(NULL, "wk", "sf")) {
    board <- new_fake_board("local_only")
    gdpins_pin_write(board, x, "parcels", wkt_engine = eng)
    got <- gdpins_pin_read(board, "parcels", wkt_engine = eng)
    expect_s3_class(got, "sf")
    expect_lt(we_max_dev(got, x), 1e-6)
    expect_equal(sf::st_crs(got), sf::st_crs(x))
  }
})

test_that("pin written with sf engine reads back with wk engine (interchange)", {
  x     <- fx_sf_multipoly_utm()
  board <- new_fake_board("local_only")
  gdpins_pin_write(board, x, "estates", wkt_engine = "sf")
  got <- gdpins_pin_read(board, "estates", wkt_engine = "wk")
  expect_lt(we_max_dev(got, x), 1e-6)
})

# ── integration: raw connection wkt_engine pass-through ────────────────────────

test_that("raw put_object/get round-trip sf parquet via wkt_engine", {
  x    <- fx_sf_poly_utm()
  conn <- new_fake_raw_conn("local_only")

  for (eng in list(NULL, "wk", "sf")) {
    gdpins_raw_put_object(conn, x, "geo/parcels.parquet", wkt_engine = eng)
    got <- gdpins_raw_get(conn, "geo/parcels.parquet", wkt_engine = eng)
    expect_s3_class(got, "sf")
    expect_lt(we_max_dev(got, x), 1e-6)
  }
})

# ── wkt_engine = "none": pin_read returns raw WKT text, no sf restoration ──────

test_that("pin_read(wkt_engine = 'none') returns WKT text, not sf", {
  x     <- fx_sf_poly_utm()
  board <- new_fake_board("local_only")
  gdpins_pin_write(board, x, "parcels")

  got <- gdpins_pin_read(board, "parcels", wkt_engine = "none")
  expect_false(inherits(got, "sf"))
  expect_s3_class(got, "data.frame")

  geo_col <- grep("__\\d{4,5}__$", names(got), value = TRUE)
  expect_length(geo_col, 1L)                # name keeps its __epsg__ suffix
  expect_type(got[[geo_col]], "character")  # geometry left as WKT text
})

test_that("pin_read(none) output feeds gdpins_as_sf() back to sf", {
  x     <- fx_sf_poly_utm()
  board <- new_fake_board("local_only")
  gdpins_pin_write(board, x, "parcels")

  txt <- gdpins_pin_read(board, "parcels", wkt_engine = "none")
  got <- gdpins_as_sf(txt)                  # standard suffix -> silent
  expect_s3_class(got, "sf")
  expect_lt(we_max_dev(got, x), 1e-6)
  expect_equal(sf::st_crs(got), sf::st_crs(x))
})

test_that("pin_read rejects an invalid wkt_engine", {
  board <- new_fake_board("local_only")
  gdpins_pin_write(board, fx_plain_tbl(), "plain")
  expect_error(
    gdpins_pin_read(board, "plain", wkt_engine = "bogus"),
    "Invalid.*wkt_engine|wkt_engine"
  )
})
