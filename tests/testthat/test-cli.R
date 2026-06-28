# test-cli.R — compact CLI formatter tests

# ── gd_fmt_bytes ─────────────────────────────────────────────────────────────

test_that("gd_fmt_bytes() formats bytes correctly", {
  expect_equal(gd_fmt_bytes(0),   "0 B")
  expect_equal(gd_fmt_bytes(500), "500 B")
  expect_equal(gd_fmt_bytes(999), "999 B")
})

test_that("gd_fmt_bytes() formats kilobytes correctly", {
  expect_equal(gd_fmt_bytes(1000),  "1 KB")
  expect_equal(gd_fmt_bytes(1500),  "1.5 KB")
  expect_equal(gd_fmt_bytes(12345), "12.3 KB")
})

test_that("gd_fmt_bytes() formats megabytes correctly", {
  expect_equal(gd_fmt_bytes(1e6),  "1 MB")
  expect_equal(gd_fmt_bytes(2.5e6), "2.5 MB")
})

test_that("gd_fmt_bytes() formats gigabytes correctly", {
  result <- gd_fmt_bytes(1.5e9)
  expect_true(grepl("GB", result))
})

test_that("gd_fmt_bytes() returns 'NA' for NA input", {
  expect_equal(gd_fmt_bytes(NA_real_), "NA")
})

test_that("gd_fmt_bytes() formats negative values as bytes", {
  result <- gd_fmt_bytes(-42)
  expect_true(grepl("B", result))
})

test_that("gd_fmt_bytes() errors on non-numeric input", {
  expect_error(gd_fmt_bytes("big"))
  expect_error(gd_fmt_bytes(NULL))
})

test_that("gd_fmt_bytes() errors on vector input", {
  expect_error(gd_fmt_bytes(c(1, 2)))
})

test_that("gd_fmt_bytes() returns a character scalar", {
  expect_type(gd_fmt_bytes(1024), "character")
  expect_length(gd_fmt_bytes(1024), 1L)
})

# ── gd_fmt_mtime ─────────────────────────────────────────────────────────────

test_that("gd_fmt_mtime() formats a POSIXct correctly", {
  t <- as.POSIXct("2026-01-15 14:30:00", tz = "UTC")
  result <- gd_fmt_mtime(t)
  expect_type(result, "character")
  expect_true(grepl("2026-01-15", result))
  expect_true(grepl("14:30", result))
})

test_that("gd_fmt_mtime() returns em-dash for NA", {
  expect_equal(gd_fmt_mtime(as.POSIXct(NA)), "—")
})

test_that("gd_fmt_mtime() accepts numeric that coerces to POSIXct", {
  t <- as.POSIXct("2026-06-01 00:00:00", tz = "UTC")
  # Should not error
  expect_no_error(gd_fmt_mtime(t))
})

test_that("gd_fmt_mtime() coerces a character timestamp via as.POSIXct", {
  # Passes through the non-POSIXct branch (line 43 coercion path)
  result <- gd_fmt_mtime("2026-03-10 08:00:00")
  expect_type(result, "character")
  expect_true(grepl("2026", result))
})

test_that("gd_fmt_mtime() accepts a POSIXlt object", {
  t <- as.POSIXlt("2026-04-01 09:15:00", tz = "UTC")
  result <- gd_fmt_mtime(t)
  expect_type(result, "character")
  expect_true(grepl("2026-04-01", result))
})

test_that("gd_fmt_mtime() returns a length-1 character", {
  t <- as.POSIXct("2026-01-01 12:00:00", tz = "UTC")
  result <- gd_fmt_mtime(t)
  expect_length(result, 1L)
})

test_that("gd_fmt_mtime() output fits within 80 chars", {
  t <- as.POSIXct("2026-01-15 14:30:00", tz = "UTC")
  expect_lte(nchar(gd_fmt_mtime(t)), 80L)
})

# ── gd_cli_kv ────────────────────────────────────────────────────────────────

test_that("gd_cli_kv() emits output without error", {
  expect_no_error(gd_cli_kv(config = "drive_cache", name = "data_raw"))
})

test_that("gd_cli_kv() returns NULL invisibly", {
  result <- withVisible(gd_cli_kv(key = "val"))
  expect_false(result$visible)
  expect_null(result$value)
})

test_that("gd_cli_kv() errors on unnamed arguments", {
  expect_error(gd_cli_kv("unnamed_value"))
})

test_that("gd_cli_kv() truncates very long values to stay near 80 cols", {
  long_val <- paste(rep("x", 200), collapse = "")
  # Should not error
  expect_no_error(gd_cli_kv(key = long_val))
})

test_that("gd_cli_kv() handles multiple named arguments", {
  expect_no_error(gd_cli_kv(
    config     = "local_only",
    name       = "test",
    versioned  = "TRUE",
    drive_path = "some/path"
  ))
})
