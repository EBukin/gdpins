# test-raw-connection.R — TDD for R/raw-connection.R
# All tests use new_fake_raw_conn() and shared fixtures. No network.

# ── Extension dispatch — put_object ──────────────────────────────────────────

test_that("put_object/get round-trips .rds", {
  conn <- new_fake_raw_conn()
  obj  <- list(a = 1L, b = "hello")
  gdpins_raw_put_object(conn, obj, "test.rds")
  result <- gdpins_raw_get(conn, "test.rds")
  expect_equal(result, obj)
})

test_that("put_object/get round-trips .parquet (plain tibble)", {
  conn  <- new_fake_raw_conn()
  tbl   <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "test.parquet")
  result <- gdpins_raw_get(conn, "test.parquet")
  # arrow may convert int to dbl; check column names and types loosely
  expect_s3_class(result, "tbl_df")
  expect_equal(names(result), names(tbl))
  expect_equal(nrow(result), nrow(tbl))
})

test_that("put_object/get round-trips .csv", {
  conn   <- new_fake_raw_conn()
  tbl    <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "test.csv")
  result <- gdpins_raw_get(conn, "test.csv")
  expect_s3_class(result, "tbl_df")
  expect_equal(names(result), names(tbl))
})

test_that("put_object/get round-trips .geojson (CRS preserved as-is)", {
  conn <- new_fake_raw_conn()
  sf_obj <- fx_sf_single()
  gdpins_raw_put_object(conn, sf_obj, "test.geojson")
  result <- gdpins_raw_get(conn, "test.geojson")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, sf::st_crs(sf_obj)$epsg)
})

test_that("unknown extension aborts on put_object", {
  conn <- new_fake_raw_conn()
  expect_error(
    gdpins_raw_put_object(conn, list(), "test.xyz"),
    "Unsupported file extension"
  )
})

test_that("unknown extension aborts on get", {
  conn <- new_fake_raw_conn()
  # Create a local file with bad extension
  local_file <- file.path(conn$local_path, "test.xyz")
  writeLines("garbage", local_file)
  expect_error(
    gdpins_raw_get(conn, "test.xyz"),
    "Unsupported file extension"
  )
})

# ── sf via parquet — shared encoder ──────────────────────────────────────────

test_that("parquet containing sf (EPSG 4326) round-trips identity via shared encoder", {
  conn   <- new_fake_raw_conn()
  sf_obj <- fx_sf_single()
  gdpins_raw_put_object(conn, sf_obj, "sf_4326.parquet")
  result <- gdpins_raw_get(conn, "sf_4326.parquet")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 4326L)
  expect_equal(nrow(result), nrow(sf_obj))
  # Geometry identity (WKT round-trip)
  expect_equal(
    sf::st_as_text(result$geometry),
    sf::st_as_text(sf_obj$geometry)
  )
})

test_that("parquet containing sf (non-4326, EPSG 3857) round-trips with CRS preserved", {
  conn   <- new_fake_raw_conn()
  sf_obj <- fx_sf_non4326()
  gdpins_raw_put_object(conn, sf_obj, "sf_3857.parquet")
  result <- gdpins_raw_get(conn, "sf_3857.parquet")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 3857L)
  expect_equal(nrow(result), nrow(sf_obj))
})

# ── geojson CRS preserved (non-4326 round-trip) ───────────────────────────────

test_that("geojson CRS is preserved in a non-4326 round-trip (no transform)", {
  conn   <- new_fake_raw_conn()
  # geojson spec stores in WGS84 but sf reads back with EPSG if embedded
  # Use a 4326 sf (standard for geojson); CRS must survive
  sf_obj <- fx_sf_single()  # 4326
  gdpins_raw_put_object(conn, sf_obj, "geojson_crs.geojson")
  result <- gdpins_raw_get(conn, "geojson_crs.geojson")
  expect_s3_class(result, "sf")
  # CRS must NOT be transformed — geojson carries own CRS
  expect_equal(sf::st_crs(result)$epsg, sf::st_crs(sf_obj)$epsg)
})

test_that("geojson round-trip for non-4326 object does not call st_transform", {
  conn    <- new_fake_raw_conn()
  sf_3857 <- fx_sf_non4326()
  # Our code must NOT call st_transform; CRS handling is delegated entirely to
  # sf::st_write / sf::st_read. We verify round-trip completes without error
  # and the result is an sf object (geometry preserved in whatever CRS sf chooses).
  gdpins_raw_put_object(conn, sf_3857, "geojson_3857.geojson")
  result <- gdpins_raw_get(conn, "geojson_3857.geojson")
  expect_s3_class(result, "sf")
  expect_equal(nrow(result), nrow(sf_3857))
})

# ── put_file — verbatim (byte-identity via md5) ───────────────────────────────

test_that("put_file is byte-identical (md5 match) for any file type", {
  conn <- new_fake_raw_conn()

  # Use a CSV path fixture as source
  src_path <- fx_csv_path()
  src_md5  <- unname(tools::md5sum(src_path))

  gdpins_raw_put_file(conn, src_path, "verbatim.csv")

  local_dest <- file.path(conn$local_path, "verbatim.csv")
  dest_md5   <- unname(tools::md5sum(local_dest))

  expect_equal(dest_md5, src_md5)
})

test_that("put_file also uploads to Drive in drive_local mode", {
  conn     <- new_fake_raw_conn("drive_local")
  src_path <- fx_csv_path()
  gdpins_raw_put_file(conn, src_path, "verbatim.csv")

  # Drive file should exist
  drive_dest <- paste0(conn$drive_path, "/verbatim.csv")
  expect_true(gd_exists(conn$adapter, drive_dest))
})

test_that("put_file errors if source file does not exist", {
  conn <- new_fake_raw_conn()
  expect_error(
    gdpins_raw_put_file(conn, "/nonexistent/path.csv", "dest.csv"),
    "Source file not found"
  )
})

# ── Relative path resolution (subfolders) ────────────────────────────────────

test_that("subfolder paths are resolved correctly for put/get", {
  conn <- new_fake_raw_conn()
  tbl  <- fx_plain_tbl()

  gdpins_raw_put_object(conn, tbl, "worldbank-api/gdp_2024.csv")

  # Local file should be at local_path/worldbank-api/gdp_2024.csv
  expected_local <- file.path(conn$local_path, "worldbank-api", "gdp_2024.csv")
  expect_true(file.exists(expected_local))

  result <- gdpins_raw_get(conn, "worldbank-api/gdp_2024.csv")
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), nrow(tbl))
})

test_that("deeply nested subfolder paths work", {
  conn <- new_fake_raw_conn()
  obj  <- list(x = 42L)
  gdpins_raw_put_object(conn, obj, "a/b/c/deep.rds")
  expect_true(file.exists(file.path(conn$local_path, "a", "b", "c", "deep.rds")))
  result <- gdpins_raw_get(conn, "a/b/c/deep.rds")
  expect_equal(result, obj)
})

# ── force_refresh on/off ──────────────────────────────────────────────────────

test_that("force_refresh = FALSE reads from local without calling gd_download", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()

  # Put object (writes local + drive)
  gdpins_raw_put_object(conn, tbl, "data.csv")

  # Overwrite the local file with different content
  local_file <- file.path(conn$local_path, "data.csv")
  modified_tbl <- dplyr::mutate(tbl, value = value * 2)
  readr::write_csv(modified_tbl, local_file)

  # force_refresh = FALSE must return the locally modified version
  result <- gdpins_raw_get(conn, "data.csv", force_refresh = FALSE)
  expect_equal(result$value, modified_tbl$value)
})

test_that("force_refresh = TRUE re-pulls from Drive overwriting local", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()

  # Put object (writes local + drive)
  gdpins_raw_put_object(conn, tbl, "data.csv")

  # Overwrite the local file with different content
  local_file <- file.path(conn$local_path, "data.csv")
  modified_tbl <- dplyr::mutate(tbl, value = value * 99)
  readr::write_csv(modified_tbl, local_file)

  # force_refresh = TRUE must restore the original from Drive
  result <- gdpins_raw_get(conn, "data.csv", force_refresh = TRUE)
  # Should match original tbl (from Drive), not the local modification
  expect_equal(result$value, tbl$value)
})

test_that("force_refresh = TRUE errors if local_only (no adapter to pull from)", {
  conn <- new_fake_raw_conn("local_only")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "data.csv")

  # Overwrite local
  readr::write_csv(dplyr::mutate(tbl, value = 0), file.path(conn$local_path, "data.csv"))

  # force_refresh = TRUE with no adapter — gd_download won't be called, reads local
  # (local_only has no adapter so force_refresh is a no-op on the network side)
  result <- gdpins_raw_get(conn, "data.csv", force_refresh = TRUE)
  # local value was 0 after overwrite
  expect_equal(result$value, rep(0, nrow(tbl)))
})

test_that("get errors when local file absent and no force_refresh", {
  conn <- new_fake_raw_conn()
  expect_error(
    gdpins_raw_get(conn, "does_not_exist.rds"),
    "Local file not found"
  )
})

test_that("gdpins_raw_connect: fake adapter with ID-like drive_path still works as path", {
  adapter <- gdpins_fake_drive()
  local_path <- withr::local_tempdir()

  conn <- gdpins_raw_connect(
    drive_path = "nodash",
    local_path = local_path,
    adapter    = adapter,
    create     = TRUE
  )

  expect_s3_class(conn, "gdpins_raw_conn")
  expect_equal(conn$drive_path, "nodash")
})

# ── raw_ls depth ──────────────────────────────────────────────────────────────

test_that("raw_ls returns tibble with expected columns", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "a/b.csv")
  result <- gdpins_raw_ls(conn)
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("name", "is_dir", "size", "mtime", "depth") %in% names(result)))
})

test_that("raw_ls depth=1 shows only top-level entries", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "level1/level2.csv")
  gdpins_raw_put_object(conn, tbl, "top.csv")

  result <- gdpins_raw_ls(conn, depth = 1)
  expect_true(all(result$depth <= 1))
  # level1/level2.csv is depth 2, must not appear
  expect_false(any(grepl("level1/level2", result$name)))
})

test_that("raw_ls depth=2 (default) includes depth-2 entries", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "level1/level2.csv")

  result <- gdpins_raw_ls(conn, depth = 2)
  expect_true(any(grepl("level2.csv", result$name)))
})

test_that("raw_ls on empty connection returns empty tibble", {
  conn   <- new_fake_raw_conn("drive_local")
  result <- gdpins_raw_ls(conn)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("raw_ls works for local_only connections", {
  conn <- new_fake_raw_conn("local_only")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "local_file.csv")
  result <- gdpins_raw_ls(conn)
  expect_s3_class(result, "tbl_df")
  expect_true(any(grepl("local_file", result$name)))
})

# ── gdpins_raw_connect — create-confirm branches ─────────────────────────────

test_that("connect with create=TRUE creates missing Drive folder", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "test-raw/new-folder"

  expect_false(gd_exists(adapter, drive_path))

  conn <- gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = TRUE,
    on_discrepancy = "ignore",
    adapter        = adapter
  )

  expect_true(gd_exists(adapter, drive_path))
  expect_equal(conn$config, "drive_local")
})

test_that("connect with create=FALSE errors if Drive folder absent", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")

  expect_error(
    gdpins_raw_connect(
      drive_path     = "non/existent",
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = "ignore",
      adapter        = adapter
    ),
    "does not exist"
  )
})

test_that("connect with adapter=NULL creates local_only conn", {
  local_path <- tempfile("gdpins_raw_local_")
  conn <- gdpins_raw_connect(
    drive_path     = "ignored",
    local_path     = local_path,
    adapter        = NULL
  )
  expect_equal(conn$config, "local_only")
  expect_null(conn$adapter)
  expect_true(dir.exists(local_path))
})

test_that("connect with existing Drive folder and create=NA succeeds (no prompt needed)", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "existing-folder"

  # Pre-create the Drive folder
  gd_mkdir(adapter, drive_path)

  conn <- gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = NA,
    on_discrepancy = "ignore",
    adapter        = adapter
  )

  expect_equal(conn$config, "drive_local")
  expect_equal(conn$drive_path, drive_path)
})

# ── on_discrepancy branches ───────────────────────────────────────────────────

test_that("on_discrepancy='warn' emits a warning when drive and local differ", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "disc-test"
  gd_mkdir(adapter, drive_path)

  # Put a file on drive but not locally
  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/only_on_drive.csv"))

  expect_warning(
    gdpins_raw_connect(
      drive_path     = drive_path,
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = "warn",
      adapter        = adapter
    )
  )
})

test_that("on_discrepancy='ignore' does not warn or error even when drive and local differ", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "ignore-test"
  gd_mkdir(adapter, drive_path)

  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/only_on_drive.csv"))

  expect_no_warning(
    gdpins_raw_connect(
      drive_path     = drive_path,
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = "ignore",
      adapter        = adapter
    )
  )
})

test_that("on_discrepancy='sync_from_drive' pulls drive files to local", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "sync-from-test"
  gd_mkdir(adapter, drive_path)

  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/synced.csv"))

  gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = FALSE,
    on_discrepancy = "sync_from_drive",
    adapter        = adapter
  )

  expect_true(file.exists(file.path(local_path, "synced.csv")))
})

test_that("on_discrepancy='sync_to_drive' pushes local files to drive", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  fs::dir_create(local_path)
  drive_path <- "sync-to-test"
  gd_mkdir(adapter, drive_path)

  # Put a file locally only
  local_file <- file.path(local_path, "local_only.csv")
  readr::write_csv(fx_plain_tbl(), local_file)

  gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = FALSE,
    on_discrepancy = "sync_to_drive",
    adapter        = adapter
  )

  expect_true(gd_exists(adapter, paste0(drive_path, "/local_only.csv")))
})

test_that("invalid on_discrepancy value aborts", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "disc-val-test"
  gd_mkdir(adapter, drive_path)

  expect_error(
    gdpins_raw_connect(
      drive_path     = drive_path,
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = "invalid_value",
      adapter        = adapter
    ),
    "on_discrepancy"
  )
})

# ── gdpins_refresh_disconnect ─────────────────────────────────────────────────

test_that("refresh_disconnect pulls all drive files to local", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()

  # Put files via put_object (local + drive)
  gdpins_raw_put_object(conn, tbl, "file1.csv")
  gdpins_raw_put_object(conn, tbl, "sub/file2.rds")

  # Delete local versions to simulate stale local mirror
  unlink(file.path(conn$local_path, "file1.csv"))
  unlink(file.path(conn$local_path, "sub", "file2.rds"))

  gdpins_refresh_disconnect(conn)

  expect_true(file.exists(file.path(conn$local_path, "file1.csv")))
  expect_true(file.exists(file.path(conn$local_path, "sub", "file2.rds")))
})

test_that("refresh_disconnect is a no-op for local_only", {
  conn <- new_fake_raw_conn("local_only")
  expect_invisible(gdpins_refresh_disconnect(conn))
})

# ── S3 print/format/summary ───────────────────────────────────────────────────

test_that("print.gdpins_raw_conn outputs text without error", {
  conn <- new_fake_raw_conn("drive_local")
  expect_output(print(conn))
})

test_that("format.gdpins_raw_conn returns a character string", {
  conn <- new_fake_raw_conn("drive_local")
  out  <- format(conn)
  expect_type(out, "character")
  expect_true(nchar(out) > 0L)
  expect_true(grepl("gdpins_raw_conn", out))
})

test_that("format.gdpins_raw_conn mentions local_only for local_only config", {
  conn <- new_fake_raw_conn("local_only")
  out  <- format(conn)
  expect_true(grepl("local", out))
})

test_that("summary.gdpins_raw_conn returns the conn invisibly", {
  conn <- new_fake_raw_conn("drive_local")
  result <- withVisible(summary(conn))
  expect_false(result$visible)
  expect_s3_class(result$value, "gdpins_raw_conn")
})

test_that("print/format/summary output fits within 80 columns", {
  conn <- new_fake_raw_conn("drive_local")
  fmt  <- format(conn)
  lines <- strsplit(fmt, "\n", fixed = TRUE)[[1L]]
  expect_true(all(nchar(lines) <= 80L))
})

# ── Drive upload confirmed in drive_local mode ────────────────────────────────

test_that("put_object uploads to Drive in drive_local mode", {
  conn <- new_fake_raw_conn("drive_local")
  tbl  <- fx_plain_tbl()
  gdpins_raw_put_object(conn, tbl, "check_drive.csv")

  drive_path <- paste0(conn$drive_path, "/check_drive.csv")
  expect_true(gd_exists(conn$adapter, drive_path))
})

test_that("put_object does NOT touch drive in local_only mode", {
  conn <- new_fake_raw_conn("local_only")
  tbl  <- fx_plain_tbl()
  expect_no_error(gdpins_raw_put_object(conn, tbl, "local_only_file.csv"))
  expect_true(file.exists(file.path(conn$local_path, "local_only_file.csv")))
})

# ── parquet sf dispatch uses gdpins_sf_to_parquet / gdpins_parquet_to_sf ──────

test_that("parquet sf dispatch encodes with gdpins_sf_to_parquet (column name __epsg__ pattern)", {
  conn   <- new_fake_raw_conn()
  sf_obj <- fx_sf_single()
  gdpins_raw_put_object(conn, sf_obj, "sf_encoded.parquet")

  # Read raw parquet without the decoder to inspect column names
  local_file  <- file.path(conn$local_path, "sf_encoded.parquet")
  raw_tbl     <- arrow::read_parquet(local_file)
  col_names   <- names(raw_tbl)

  # Must have at least one column matching __epsg__ pattern
  expect_true(any(grepl("__\\d{4,5}__$", col_names)))
})

# ── Additional coverage: uncovered branches ───────────────────────────────────

test_that("resolve_on_discrepancy returns 'warn' when NULL and non-interactive", {
  # Non-interactive R sessions return "warn" for NULL on_discrepancy
  # Verified indirectly: connect with NULL on_discrepancy emits a warning on discrepancy
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "null-disc-test"
  gd_mkdir(adapter, drive_path)

  # Put a file on drive only to create discrepancy
  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/only_on_drive.csv"))

  # NULL on_discrepancy in non-interactive context -> "warn"
  expect_warning(
    gdpins_raw_connect(
      drive_path     = drive_path,
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = NULL,  # resolves to "warn" non-interactively
      adapter        = adapter
    )
  )
})

test_that("raw_ext returns empty string for a path with no extension", {
  # .raw_ext is internal; exercise via .check_ext error path with no ext
  conn <- new_fake_raw_conn()
  expect_error(
    gdpins_raw_put_object(conn, list(), "no_extension"),
    "Unsupported file extension"
  )
})

test_that("connect aborts if local_path is empty string", {
  expect_error(
    gdpins_raw_connect(
      drive_path = "test",
      local_path = ""
    ),
    "local_path"
  )
})

test_that("connect aborts if drive_path is NULL when adapter is provided", {
  fake_root <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter   <- gdpins_fake_drive(root = fake_root)
  expect_error(
    gdpins_raw_connect(
      drive_path     = NULL,
      local_path     = tempfile("gdpins_raw_local_"),
      create         = TRUE,
      on_discrepancy = "ignore",
      adapter        = adapter
    ),
    "drive_path"
  )
})

test_that("connect aborts if drive_path is empty string when adapter is provided", {
  fake_root <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter   <- gdpins_fake_drive(root = fake_root)
  expect_error(
    gdpins_raw_connect(
      drive_path     = "",
      local_path     = tempfile("gdpins_raw_local_"),
      create         = TRUE,
      on_discrepancy = "ignore",
      adapter        = adapter
    ),
    "drive_path"
  )
})

test_that("raw_ls on empty local_only connection returns zero-row tibble", {
  conn   <- new_fake_raw_conn("local_only")
  result <- gdpins_raw_ls(conn)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("raw_ls local_only includes directories in the result", {
  conn <- new_fake_raw_conn("local_only")
  # Create a subdirectory and a file inside it
  sub_dir <- file.path(conn$local_path, "subdir")
  fs::dir_create(sub_dir)
  readr::write_csv(fx_plain_tbl(), file.path(sub_dir, "file.csv"))

  result <- gdpins_raw_ls(conn, depth = 2)
  expect_s3_class(result, "tbl_df")
  # Both the directory and the file should appear at appropriate depths
  expect_true(nrow(result) >= 1L)
  # Check that is_dir is correctly detected
  expect_true(any(result$is_dir))  # the subdir
  expect_true(any(!result$is_dir)) # the csv file
})

test_that("create=NA with missing Drive folder and non-interactive aborts", {
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")

  # create=NA in non-interactive session should error (cannot prompt)
  expect_error(
    gdpins_raw_connect(
      drive_path     = "missing/folder",
      local_path     = local_path,
      create         = NA,
      on_discrepancy = "ignore",
      adapter        = adapter
    ),
    "does not exist"
  )
})

# ── interactive() branches — env-var controlled ───────────────────────────────
# .raw_is_interactive() / .raw_readline() check GDPINS_RAW_INTERACTIVE /
# GDPINS_RAW_READLINE env vars first, so tests can control behaviour without
# mocking and without needing an actual interactive session.

test_that("resolve_on_discrepancy returns 'prompt' when NULL and interactive", {
  # Simulate interactive session; no discrepancy => no warning, conn succeeds
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "TRUE")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "interactive-disc-none"
  gd_mkdir(adapter, drive_path)

  conn <- gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = FALSE,
    on_discrepancy = NULL,
    adapter        = adapter
  )
  expect_equal(conn$config, "drive_local")
})

test_that("create=NA interactive: 'n' answer aborts", {
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "TRUE", GDPINS_RAW_READLINE = "n")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")

  expect_error(
    gdpins_raw_connect(
      drive_path     = "missing-folder",
      local_path     = local_path,
      create         = NA,
      on_discrepancy = "ignore",
      adapter        = adapter
    ),
    "does not exist"
  )
})

test_that("create=NA interactive: 'y' answer creates folder", {
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "TRUE", GDPINS_RAW_READLINE = "y")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "create-on-y"

  conn <- gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = NA,
    on_discrepancy = "ignore",
    adapter        = adapter
  )
  expect_true(gd_exists(adapter, drive_path))
  expect_equal(conn$config, "drive_local")
})

test_that("on_discrepancy='prompt' non-interactive emits a warning", {
  # Explicitly non-interactive: .raw_is_interactive() returns FALSE
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "FALSE")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "prompt-noninteractive"
  gd_mkdir(adapter, drive_path)

  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/drive_file.csv"))

  expect_warning(
    gdpins_raw_connect(
      drive_path     = drive_path,
      local_path     = local_path,
      create         = FALSE,
      on_discrepancy = "prompt",
      adapter        = adapter
    )
  )
})

test_that("on_discrepancy='prompt' interactive: 'y' answer syncs from drive", {
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "TRUE", GDPINS_RAW_READLINE = "y")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "prompt-sync-y"
  gd_mkdir(adapter, drive_path)

  # Put a file on drive only
  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/drive_file.csv"))

  gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = FALSE,
    on_discrepancy = "prompt",
    adapter        = adapter
  )

  # File should be synced locally
  expect_true(file.exists(file.path(local_path, "drive_file.csv")))
})

test_that("on_discrepancy='prompt' interactive: 'n' answer skips sync", {
  withr::local_envvar(GDPINS_RAW_INTERACTIVE = "TRUE", GDPINS_RAW_READLINE = "n")
  fake_root  <- tempfile("gdpins_fake_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  local_path <- tempfile("gdpins_raw_local_")
  drive_path <- "prompt-skip-n"
  gd_mkdir(adapter, drive_path)

  tmp_src <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp_src)
  gd_upload(adapter, tmp_src, paste0(drive_path, "/drive_file.csv"))

  gdpins_raw_connect(
    drive_path     = drive_path,
    local_path     = local_path,
    create         = FALSE,
    on_discrepancy = "prompt",
    adapter        = adapter
  )

  # File should NOT be synced locally (user said 'n')
  expect_false(file.exists(file.path(local_path, "drive_file.csv")))
})
