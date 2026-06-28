# test-pipeline.R — WS9 full e2e pipeline on fake Drive (ADR §4, §12)
#
# Full flow: raw-exogenous → data-raw → data-interm → data-clean → output
# Carries a plain tibble AND an sf object; asserts sf survives end-to-end
# with CRS intact.
#
# All boards backed by fake Drive — no network, no auth.

# ── Helper: shared fake adapter + multi-board setup ───────────────────────────

.make_pipeline_env <- function() {
  fake_root <- tempfile("gdpins_pipeline_")
  fs::dir_create(fake_root)
  adapter <- gdpins_fake_drive(root = fake_root)

  make_board <- function(name, drive_sub) {
    drive_path <- paste0("kazLandEconImpact-data/", drive_sub)
    cache_dir  <- tempfile(paste0("gdpins_", name, "_cache_"))
    fs::dir_create(cache_dir)
    gd_mkdir(adapter, drive_path)
    new_fake_board_custom(
      name       = name,
      drive_path = drive_path,
      cache_dir  = cache_dir,
      adapter    = adapter
    )
  }

  raw_conn_local <- tempfile("gdpins_raw_local_")
  fs::dir_create(raw_conn_local)
  drive_raw <- "kazLandEconImpact-data/raw-exogenous"
  gd_mkdir(adapter, drive_raw)

  raw_conn <- new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = drive_raw,
    local_path = raw_conn_local,
    adapter    = adapter
  )

  list(
    adapter  = adapter,
    raw_conn = raw_conn,
    bd_raw   = make_board("data_raw",   "data-raw"),
    bd_interm = make_board("data_interm", "data-interm"),
    bd_clean  = make_board("data_clean",  "data-clean"),
    bd_output = make_board("output_tables", "output-tables"),
    fig_dir   = tempfile("gdpins_figures_")
  )
}

# Custom helper because new_fake_board doesn't accept a shared adapter
new_fake_board_custom <- function(name, drive_path, cache_dir, adapter) {
  drive_board_dir <- file.path(
    adapter$root,
    gsub("/", .Platform$file.sep, drive_path, fixed = TRUE)
  )
  fs::dir_create(drive_board_dir)
  drive_board <- pins::board_folder(drive_board_dir, versioned = TRUE)
  cache_board <- pins::board_folder(cache_dir,       versioned = TRUE)
  new_gdpins_board(
    config      = "drive_cache",
    name        = name,
    drive_board = drive_board,
    cache_board = cache_board,
    cache_dir   = cache_dir,
    drive_path  = drive_path,
    adapter     = adapter,
    versioned   = TRUE
  )
}

# ── Pipeline tests (plain tibble path) ───────────────────────────────────────

test_that("plain tibble flows raw → data_raw → data_interm → data_clean", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env   <- .make_pipeline_env()
  tbl   <- fx_plain_tbl()
  concept <- "gdp_panel"

  # Step 1: raw-exogenous — put object to raw conn
  suppressMessages(
    gdpins_raw_put_object(env$raw_conn, tbl, paste0(concept, ".rds"))
  )

  # Step 2: retrieve from raw conn, write to data_raw board
  raw_data <- suppressMessages(
    gdpins_raw_get(env$raw_conn, paste0(concept, ".rds"))
  )
  suppressMessages(gdpins_pin_write(env$bd_raw, raw_data, concept))

  # Step 3: read from data_raw, transform, write to data_interm
  interm_data <- gdpins_pin_read(env$bd_raw, concept)
  interm_data <- dplyr::mutate(interm_data, value_scaled = value / max(value))
  suppressMessages(gdpins_pin_write(env$bd_interm, interm_data, concept))

  # Step 4: read from data_interm, finalize, write to data_clean
  clean_data <- gdpins_pin_read(env$bd_interm, concept)
  clean_data <- dplyr::filter(clean_data, flag == TRUE)
  suppressMessages(gdpins_pin_write(env$bd_clean, clean_data, concept))

  # Verify: concept name preserved across all layers
  expect_true(pins::pin_exists(env$bd_raw$cache_board,   concept))
  expect_true(pins::pin_exists(env$bd_interm$cache_board, concept))
  expect_true(pins::pin_exists(env$bd_clean$cache_board,  concept))

  # Verify data integrity at the clean layer
  final <- gdpins_pin_read(env$bd_clean, concept)
  expect_s3_class(final, "data.frame")
  expect_true(all(final$flag == TRUE))
})

test_that("plain tibble concept name is identical across all board layers", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  concept <- "land_transactions"

  suppressMessages(gdpins_pin_write(env$bd_raw,   fx_plain_tbl(), concept))
  suppressMessages(gdpins_pin_write(env$bd_interm, fx_plain_tbl(), concept))
  suppressMessages(gdpins_pin_write(env$bd_clean,  fx_plain_tbl(), concept))

  raw_pins   <- pins::pin_list(env$bd_raw$cache_board)
  interm_pins <- pins::pin_list(env$bd_interm$cache_board)
  clean_pins  <- pins::pin_list(env$bd_clean$cache_board)

  expect_true(concept %in% raw_pins)
  expect_true(concept %in% interm_pins)
  expect_true(concept %in% clean_pins)
})

# ── Pipeline tests (sf / geospatial path) ────────────────────────────────────

test_that("sf object (EPSG 4326) survives raw → data_raw → data_clean with CRS intact", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  sf_obj  <- fx_sf_single()
  concept <- "parcels"

  # raw-exogenous: store as .parquet (uses sf encoder)
  suppressMessages(
    gdpins_raw_put_object(env$raw_conn, sf_obj, paste0(concept, ".parquet"))
  )

  # Retrieve and assert CRS
  raw_result <- suppressMessages(
    gdpins_raw_get(env$raw_conn, paste0(concept, ".parquet"))
  )
  expect_equal(sf::st_crs(raw_result)$epsg, 4326L)

  # data_raw board
  suppressMessages(gdpins_pin_write(env$bd_raw, sf_obj, concept))
  raw_read <- gdpins_pin_read(env$bd_raw, concept)
  expect_equal(sf::st_crs(raw_read)$epsg, 4326L)

  # data_interm
  suppressMessages(gdpins_pin_write(env$bd_interm, raw_read, concept))
  interm_read <- gdpins_pin_read(env$bd_interm, concept)
  expect_equal(sf::st_crs(interm_read)$epsg, 4326L)

  # data_clean
  suppressMessages(gdpins_pin_write(env$bd_clean, interm_read, concept))
  clean_read <- gdpins_pin_read(env$bd_clean, concept)

  expect_s3_class(clean_read, "sf")
  expect_equal(sf::st_crs(clean_read)$epsg, 4326L)

  # Geometry values preserved
  expect_equal(nrow(clean_read), nrow(sf_obj))
})

test_that("sf with non-4326 CRS (EPSG 3857) survives full pipeline", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  sf_obj  <- fx_sf_non4326()  # EPSG 3857
  concept <- "cadastre_3857"

  suppressMessages(gdpins_pin_write(env$bd_raw,   sf_obj, concept))
  suppressMessages(gdpins_pin_write(env$bd_interm, sf_obj, concept))
  suppressMessages(gdpins_pin_write(env$bd_clean,  sf_obj, concept))

  clean_read <- gdpins_pin_read(env$bd_clean, concept)
  expect_s3_class(clean_read, "sf")
  expect_equal(sf::st_crs(clean_read)$epsg, 3857L)
})

test_that("multi-geometry sf (differing CRS per column) round-trips through pipeline", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  sf_obj  <- fx_sf_multi_crs()
  concept <- "parcels_multi"

  suppressMessages(gdpins_pin_write(env$bd_clean, sf_obj, concept))
  result <- gdpins_pin_read(env$bd_clean, concept)

  expect_s3_class(result, "sf")
  expect_equal(nrow(result), nrow(sf_obj))
  # Both geometry columns should survive
  geo_cols_orig   <- names(sf_obj)[vapply(sf_obj, inherits, logical(1L), "sfc")]
  geo_cols_result <- names(result)[vapply(result, inherits, logical(1L), "sfc")]
  expect_equal(length(geo_cols_result), length(geo_cols_orig))
})

# ── Output layer ──────────────────────────────────────────────────────────────

test_that("output table written to output board and published to Drive", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env    <- .make_pipeline_env()
  output <- fx_output_table()

  suppressMessages(gdpins_pin_write(env$bd_output, output, "summary_table"))
  expect_true(pins::pin_exists(env$bd_output$cache_board, "summary_table"))

  # Publish to Drive (using the adapter from output board)
  suppressMessages(
    gdpins_publish_output(
      tables_board = env$bd_output,
      adapter      = env$adapter,
      dry_run      = FALSE
    )
  )

  # Verify the RDS file was uploaded to Drive
  published_path <- paste0("output-tables/summary_table.rds")
  expect_true(gd_exists(env$adapter, published_path))
})

test_that("figure saved then published to Drive", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  fig_dir <- env$fig_dir
  fs::dir_create(fig_dir)

  # Save figure
  fig_path <- suppressMessages(
    gdpins_save_figure(fx_ggplot(), name = "plot_gdp", dir = fig_dir)
  )
  expect_true(file.exists(fig_path))
  expect_true(grepl("\\.png$", fig_path))

  # Publish figures
  suppressMessages(
    gdpins_publish_output(
      figures_dir   = fig_dir,
      drive_figures = "output-figures",
      adapter       = env$adapter,
      dry_run       = FALSE
    )
  )

  expect_true(gd_exists(env$adapter, "output-figures/plot_gdp.png"))
})

test_that("dry_run publish reports items without uploading", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env    <- .make_pipeline_env()
  output <- fx_output_table()

  suppressMessages(gdpins_pin_write(env$bd_output, output, "dry_table"))

  msgs <- testthat::capture_messages(
    gdpins_publish_output(
      tables_board = env$bd_output,
      adapter      = env$adapter,
      dry_run      = TRUE
    )
  )
  msg_combined <- paste(msgs, collapse = " ")
  expect_true(grepl("Dry-run|dry.run|would be published", msg_combined,
                    ignore.case = TRUE))

  # Nothing actually uploaded
  expect_false(gd_exists(env$adapter, "output-tables/dry_table.rds"))
})

# ── Full e2e pipeline ─────────────────────────────────────────────────────────

test_that("complete pipeline: raw → interm → clean → output → publish (table + sf)", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  env     <- .make_pipeline_env()
  concept <- "parcels"

  # Step 1: raw connection deposit
  sf_src <- fx_sf_single()
  suppressMessages(
    gdpins_raw_put_object(env$raw_conn, sf_src, paste0(concept, ".parquet"))
  )

  # Step 2: ingest to data_raw
  ingest <- suppressMessages(
    gdpins_raw_get(env$raw_conn, paste0(concept, ".parquet"))
  )
  suppressMessages(gdpins_pin_write(env$bd_raw, ingest, concept))

  # Step 3: process to data_interm
  interm <- gdpins_pin_read(env$bd_raw, concept)
  suppressMessages(gdpins_pin_write(env$bd_interm, interm, concept))

  # Step 4: finalize to data_clean
  clean <- gdpins_pin_read(env$bd_interm, concept)
  suppressMessages(gdpins_pin_write(env$bd_clean, clean, concept))

  # Step 5: write output summary table
  summary_tbl <- fx_output_table()
  suppressMessages(gdpins_pin_write(env$bd_output, summary_tbl, "output_summary"))

  # Step 6: save figure
  fig_dir <- env$fig_dir
  fs::dir_create(fig_dir)
  suppressMessages(
    gdpins_save_figure(fx_ggplot(), "pipeline_figure", fig_dir)
  )

  # Step 7: publish
  suppressMessages(
    gdpins_publish_output(
      tables_board  = env$bd_output,
      figures_dir   = fig_dir,
      drive_tables  = "output-tables",
      drive_figures = "output-figures",
      adapter       = env$adapter
    )
  )

  # Assertions: concept name preserved across layers
  expect_true(pins::pin_exists(env$bd_raw$cache_board,    concept))
  expect_true(pins::pin_exists(env$bd_interm$cache_board, concept))
  expect_true(pins::pin_exists(env$bd_clean$cache_board,  concept))

  # sf CRS preserved at data_clean
  final_sf <- gdpins_pin_read(env$bd_clean, concept)
  expect_s3_class(final_sf, "sf")
  expect_equal(sf::st_crs(final_sf)$epsg, 4326L)

  # Output published
  expect_true(gd_exists(env$adapter, "output-tables/output_summary.rds"))
  expect_true(gd_exists(env$adapter, "output-figures/pipeline_figure.png"))
})
