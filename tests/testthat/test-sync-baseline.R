# test-sync-baseline.R -- H6: last-synced baseline for conflict detection.
#
# Without a record of the last synced content, "newer wins" turns a pin or
# file that changed on BOTH sides into a one-way copy. The baseline (board:
# <cache_dir>/.gdpins-sync.rds; raw: <gdpins.cache_dir>/.gdpins-raw-baselines/
# <key>.rds) lets status tell "one side moved" from "both sides moved".

# -- Helpers -------------------------------------------------------------------

board_baseline_file <- function(b) file.path(b$cache_dir, ".gdpins-sync.rds")

raw_baseline_file <- function(conn) {
  key <- rlang::hash(list(
    root       = basename(conn$adapter$root),
    drive_path = conn$drive_path,
    local_path = as.character(fs::path_norm(fs::path_abs(conn$local_path)))
  ))
  file.path(getOption("gdpins.cache_dir"), ".gdpins-raw-baselines",
            paste0(key, ".rds"))
}

raw_drive_file <- function(conn, name) {
  file.path(conn$adapter$root,
            gsub("/", .Platform$file.sep,
                 paste0(conn$drive_path, "/", name), fixed = TRUE))
}

latest_hash <- function(board, name) {
  v <- pins::pin_versions(board, name)
  v$hash[[nrow(v)]]
}

# -- 1. Versioned board: two-sided edit is a conflict --------------------------

test_that("versioned board: edits on both sides since the last sync are a conflict", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(gdpins_pin_write(b, data.frame(x = 0), "p", format = "rds"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 1), "p"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 2), "p"))

  h_local <- latest_hash(b$local_board, "p")
  h_drive <- latest_hash(b$drive_board, "p")

  # Drive is newer, but local also moved on from the synced content.
  expect_identical(gdpins_board_status(b)$state, "conflict")

  # A versioned board resolves the conflict without loss (on_conflict is
  # ignored there): both edits become versions on both boards, the newer
  # (Drive) is the latest on both.
  suppressMessages(gdpins_sync(b))
  expect_true(h_local %in% pins::pin_versions(b$drive_board, "p")$hash)
  expect_true(h_drive %in% pins::pin_versions(b$local_board, "p")$hash)
  expect_identical(pins::pin_read(b$local_board, "p")$x, 2)
  expect_identical(pins::pin_read(b$drive_board, "p")$x, 2)
  expect_identical(gdpins_board_status(b)$state, "in_sync")
})

# -- 2. Unversioned board: two-sided edit stops, both sides kept ---------------

test_that("unversioned board: two-sided edit is a conflict and stop keeps both sides", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = FALSE)

  suppressMessages(gdpins_pin_write(b, data.frame(x = 0), "p", format = "rds"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 1), "p"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 2), "p"))

  expect_identical(gdpins_board_status(b)$state, "conflict")

  expect_error(
    suppressMessages(gdpins_sync(b, on_conflict = "stop")),
    class = "gdpins_error_sync_conflict"
  )
  expect_identical(pins::pin_read(b$local_board, "p")$x, 1)
  expect_identical(pins::pin_read(b$drive_board, "p")$x, 2)
})

# -- 3. Raw: two-sided edit with clock skew is a conflict ----------------------

test_that("raw: two-sided edit is a conflict even when Drive's mtime is older", {
  withr::local_options(gdpins.cache_dir = withr::local_tempdir())
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  conn <- new_fake_raw_conn("drive_local")

  gdpins_raw_put_object(conn, data.frame(x = 0), "f.csv")

  local_file <- file.path(conn$local_path, "f.csv")
  write.csv(data.frame(x = 1), local_file, row.names = FALSE)

  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 2), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/f.csv"))
  drive_file <- raw_drive_file(conn, "f.csv")
  # Drive clock behind: its copy looks older than the local edit.
  Sys.setFileTime(drive_file, file.mtime(local_file) - 60)

  local_bytes <- readBin(local_file, "raw", 1e4)
  drive_bytes <- readBin(drive_file, "raw", 1e4)

  expect_identical(gdpins_board_status(conn)$state, "conflict")
  expect_error(
    suppressMessages(gdpins_sync(conn, on_conflict = "stop")),
    class = "gdpins_error_sync_conflict"
  )
  expect_identical(readBin(local_file, "raw", 1e4), local_bytes)
  expect_identical(readBin(drive_file, "raw", 1e4), drive_bytes)
})

# -- 4. One-sided changes ------------------------------------------------------

test_that("board: a change on one side only is *_ahead for that side", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(gdpins_pin_write(b, data.frame(x = 0), "p_drive", format = "rds"))
  suppressMessages(gdpins_pin_write(b, data.frame(x = 0), "p_local", format = "rds"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 1), "p_drive"))
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 1), "p_local"))

  st <- gdpins_board_status(b)
  expect_identical(st$state[st$name == "p_drive"], "drive_ahead")
  expect_identical(st$state[st$name == "p_local"], "local_ahead")
})

test_that("raw: a Drive-only change is drive_ahead even when Drive's mtime is older", {
  withr::local_options(gdpins.cache_dir = withr::local_tempdir())
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  conn <- new_fake_raw_conn("drive_local")

  gdpins_raw_put_object(conn, data.frame(x = 0), "f.csv")
  local_file <- file.path(conn$local_path, "f.csv")

  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 2), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/f.csv"))
  Sys.setFileTime(raw_drive_file(conn, "f.csv"), file.mtime(local_file) - 60)

  expect_identical(gdpins_board_status(conn)$state, "drive_ahead")

  # Sync pulls Drive's content instead of pushing the stale local copy.
  suppressMessages(gdpins_sync(conn))
  expect_identical(
    unname(tools::md5sum(local_file)),
    unname(tools::md5sum(tmp))
  )
})

# -- 5. Backward compatibility -------------------------------------------------

test_that("board without a baseline uses the timestamp rule; sync records one", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = TRUE)

  # Seeded directly: no gdpins verb, so no baseline file.
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 1), "a"))
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 1), "a"))
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 2), "b"))
  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 3), "c"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 4), "c"))
  expect_false(file.exists(board_baseline_file(b)))

  expect_no_warning(st <- gdpins_board_status(b))
  expect_identical(st$state[st$name == "a"], "in_sync")
  expect_identical(st$state[st$name == "b"], "local_ahead")
  expect_identical(st$state[st$name == "c"], "drive_ahead")

  suppressMessages(gdpins_sync(b))

  expect_true(file.exists(board_baseline_file(b)))
  base <- readRDS(board_baseline_file(b))
  expect_setequal(base$name, c("a", "b", "c"))
  expect_true(all(c("drive_hash", "local_hash", "synced_at") %in% names(base)))
  for (nm in c("a", "b", "c")) {
    expect_identical(base$drive_hash[base$name == nm], latest_hash(b$drive_board, nm))
    expect_identical(base$local_hash[base$name == nm], latest_hash(b$local_board, nm))
  }
  expect_setequal(pins::pin_list(b$local_board), c("a", "b", "c"))
})

# -- 6. Hygiene ----------------------------------------------------------------

test_that("gdpins_pin_remove drops the pin's baseline row", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(gdpins_pin_write(b, data.frame(x = 1), "p", format = "rds"))
  suppressMessages(gdpins_pin_write(b, data.frame(x = 2), "q", format = "rds"))
  expect_setequal(readRDS(board_baseline_file(b))$name, c("p", "q"))

  gdpins_pin_remove(b, "p")
  expect_identical(readRDS(board_baseline_file(b))$name, "q")
})

test_that("gdpins_raw_remove drops the file's baseline row", {
  withr::local_options(gdpins.cache_dir = withr::local_tempdir())
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  conn <- new_fake_raw_conn("drive_local")

  gdpins_raw_put_object(conn, data.frame(x = 1), "f.csv")
  gdpins_raw_put_object(conn, data.frame(x = 2), "g.csv")
  expect_setequal(readRDS(raw_baseline_file(conn))$name, c("f.csv", "g.csv"))

  gdpins_raw_remove(conn, "f.csv")
  expect_identical(readRDS(raw_baseline_file(conn))$name, "g.csv")
})

test_that("a corrupt baseline file warns once and falls back to the timestamp rule", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  b <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(pins::pin_write(b$local_board, data.frame(x = 1), "p"))
  Sys.sleep(1.1)
  suppressMessages(pins::pin_write(b$drive_board, data.frame(x = 2), "p"))
  writeLines("not an rds file", board_baseline_file(b))

  w <- testthat::capture_warnings(st <- gdpins_board_status(b))
  expect_length(w, 1L)
  expect_warning(
    gdpins_board_status(b),
    class = "gdpins_warning_baseline_unreadable"
  )
  expect_identical(st$state, "drive_ahead")
})
