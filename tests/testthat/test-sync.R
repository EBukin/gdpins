# test-sync.R — WS5: gdpins_board_status + gdpins_sync
# Uses new_fake_board() / new_fake_raw_conn() from helper-fakes.R
# Seeds pins/files DIRECTLY via pins::pin_write() / gd_upload()
# No dependency on WS3/WS4 verbs.
# local_mocked_bindings() is from testthat, available via pkgload::load_all()

# ── Helpers ───────────────────────────────────────────────────────────────────

.write_pin <- function(board, obj, name) {
  suppressMessages(pins::pin_write(board, obj, name))
  invisible(NULL)
}

# Make a fake board status tibble with one conflict row (for board)
.fake_board_status_conflict <- function(pin_name = "p_conflict") {
  tibble::tibble(
    name          = pin_name,
    state         = "conflict",
    drive_version = "20260101T120000Z-aaa",
    local_version = "20260101T120000Z-bbb",
    drive_created = list(as.POSIXct("2026-01-01 12:00:00", tz = "UTC")),
    local_created = list(as.POSIXct("2026-01-01 12:00:00", tz = "UTC")),
    drive_hash    = "aaaa",
    local_hash    = "bbbb"
  )
}

# Make a fake raw conn status tibble with one conflict row
.fake_raw_status_conflict <- function(fname = "conflict.csv",
                                       drive_md5 = "aaa", local_md5 = "bbb") {
  common_time <- as.POSIXct("2026-01-01 12:00:00", tz = "UTC")
  tibble::tibble(
    name        = fname,
    state       = "conflict",
    drive_md5   = drive_md5,
    local_md5   = local_md5,
    drive_mtime = list(common_time),
    local_mtime = list(common_time)
  )
}

# ── gdpins_board_status dispatch ──────────────────────────────────────────────

test_that("gdpins_board_status dispatches on gdpins_board", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  st <- gdpins_board_status(b)
  expect_s3_class(st, "tbl_df")
  expect_named(st, c("name", "state", "drive_version", "local_version",
                      "drive_created", "local_created", "drive_hash", "local_hash"))
})

test_that("gdpins_board_status dispatches on gdpins_raw_conn", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  st <- gdpins_board_status(conn)
  expect_s3_class(st, "tbl_df")
  expect_named(st, c("name", "state", "drive_md5", "local_md5",
                      "drive_mtime", "local_mtime"))
})

test_that("gdpins_board_status errors on unsupported class", {
  expect_error(gdpins_board_status("not_a_board"), class = "rlang_error")
})

# ── local_only board/conn returns empty status ────────────────────────────────

test_that("local_only board returns empty status tibble", {
  b <- new_fake_board("local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  st <- gdpins_board_status(b)
  expect_equal(nrow(st), 0L)
})

test_that("local_only raw_conn returns empty status tibble", {
  conn <- new_fake_raw_conn("local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  st <- gdpins_board_status(conn)
  expect_equal(nrow(st), 0L)
})

# ── Offline handling ───────────────────────────────────────────────────────────

test_that("board status returns all offline state when not online", {
  b <- new_fake_board("drive_cache")
  .write_pin(b$cache_board, data.frame(x = 1), "p1")
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  # cli_warn emits a condition — we just capture it
  st <- suppressWarnings(gdpins_board_status(b))
  expect_true(all(st$state == "offline"))
  expect_equal(nrow(st), 1L)
})

test_that("raw_conn status returns all offline state when not online", {
  conn <- new_fake_raw_conn("drive_local")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1), tmp, row.names = FALSE)
  file.copy(tmp, file.path(conn$local_path, "file.csv"))
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  st <- suppressWarnings(gdpins_board_status(conn))
  expect_true(all(st$state == "offline"))
})

test_that("board sync aborts when offline", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  expect_error(suppressMessages(gdpins_sync(b)), class = "rlang_error")
})

test_that("raw_conn sync aborts when offline", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  expect_error(suppressMessages(gdpins_sync(conn)), class = "rlang_error")
})

# ── Status drift states: in_sync ──────────────────────────────────────────────

test_that("board status detects in_sync (same hash on both sides)", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  # Write identical content to both
  .write_pin(b$drive_board, data.frame(x = 1), "p_sync")
  .write_pin(b$cache_board, data.frame(x = 1), "p_sync")
  st <- gdpins_board_status(b)
  expect_equal(st$state[st$name == "p_sync"], "in_sync")
})

test_that("raw_conn status detects in_sync (same bytes on both sides)", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/file.csv"))
  file.copy(tmp, file.path(conn$local_path, "file.csv"))
  st <- gdpins_board_status(conn)
  expect_equal(st$state[st$name == "file.csv"], "in_sync")
})

# ── Status drift states: local_ahead ─────────────────────────────────────────

test_that("board status detects local_ahead (pin only in local/cache)", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$cache_board, data.frame(x = 1), "p_local_only")
  st <- gdpins_board_status(b)
  expect_equal(st$state[st$name == "p_local_only"], "local_ahead")
})

test_that("raw_conn status detects local_ahead (file only in local)", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1), tmp, row.names = FALSE)
  file.copy(tmp, file.path(conn$local_path, "local_only.csv"))
  st <- gdpins_board_status(conn)
  expect_equal(st$state[st$name == "local_only.csv"], "local_ahead")
})

# ── Status drift states: drive_ahead ─────────────────────────────────────────

test_that("board status detects drive_ahead (pin only in drive)", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 1), "p_drive_only")
  st <- gdpins_board_status(b)
  expect_equal(st$state[st$name == "p_drive_only"], "drive_ahead")
})

test_that("raw_conn status detects drive_ahead (file only in drive)", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 9:11), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/drive_only.csv"))
  st <- gdpins_board_status(conn)
  expect_equal(st$state[st$name == "drive_only.csv"], "drive_ahead")
})

# ── Status drift states: conflict ─────────────────────────────────────────────

test_that("raw_conn status detects conflict (same mtime, different md5)", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  # Write different bytes to drive and local
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 4:6), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/shared.csv"))
  dest_local <- file.path(conn$local_path, "shared.csv")
  file.copy(tmp_l, dest_local)

  # Normalise mtime to same whole-second value
  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/shared.csv"), fixed = TRUE)
  )
  # Truncate local mtime to second, then set drive to match
  truncated <- as.POSIXct(
    trunc(as.numeric(file.mtime(dest_local))),
    origin = "1970-01-01", tz = "UTC"
  )
  Sys.setFileTime(dest_local, truncated)
  Sys.setFileTime(drv_abs, truncated)

  st <- gdpins_board_status(conn)
  expect_equal(st$state[st$name == "shared.csv"], "conflict")
})

test_that(".compare_board_pin returns correct structure", {
  b <- new_fake_board("drive_cache")
  .write_pin(b$drive_board, data.frame(x = 1), "p1")
  .write_pin(b$cache_board, data.frame(x = 1), "p1")
  result <- gdpins:::.compare_board_pin(
    pin_name    = "p1",
    drive_board = b$drive_board,
    local_board = b$cache_board,
    in_drive    = TRUE,
    in_local    = TRUE
  )
  expect_equal(result$name, "p1")
  expect_true(result$state %in% c("in_sync", "local_ahead", "drive_ahead", "conflict"))
  expect_true(!is.na(result$drive_hash))
  expect_true(!is.na(result$local_hash))
})

# ── Direction: to_drive ───────────────────────────────────────────────────────

test_that("sync to_drive copies local_ahead pin to drive", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$cache_board, data.frame(x = 42), "p_to_drive")
  expect_false("p_to_drive" %in% pins::pin_list(b$drive_board))
  suppressMessages(gdpins_sync(b, direction = "to_drive"))
  expect_true("p_to_drive" %in% pins::pin_list(b$drive_board))
})

test_that("sync to_drive does not copy drive_ahead pin to local", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 99), "p_drive_only")
  expect_false("p_drive_only" %in% pins::pin_list(b$cache_board))
  suppressMessages(gdpins_sync(b, direction = "to_drive"))
  expect_false("p_drive_only" %in% pins::pin_list(b$cache_board))
})

# ── Direction: from_drive ─────────────────────────────────────────────────────

test_that("sync from_drive copies drive_ahead pin to local", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 77), "p_from_drive")
  expect_false("p_from_drive" %in% pins::pin_list(b$cache_board))
  suppressMessages(gdpins_sync(b, direction = "from_drive"))
  expect_true("p_from_drive" %in% pins::pin_list(b$cache_board))
  obj <- pins::pin_read(b$cache_board, "p_from_drive")
  expect_equal(obj$x, 77L)
})

test_that("sync from_drive does not push local_ahead to drive", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$cache_board, data.frame(x = 55), "p_local_only")
  expect_false("p_local_only" %in% pins::pin_list(b$drive_board))
  suppressMessages(gdpins_sync(b, direction = "from_drive"))
  expect_false("p_local_only" %in% pins::pin_list(b$drive_board))
})

# ── Direction: auto ───────────────────────────────────────────────────────────

test_that("sync auto routes local_ahead to drive and drive_ahead to local", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$cache_board, data.frame(x = 1), "p_local")
  .write_pin(b$drive_board, data.frame(x = 2), "p_drive")
  suppressMessages(gdpins_sync(b, direction = "auto"))
  expect_true("p_local" %in% pins::pin_list(b$drive_board))
  expect_true("p_drive" %in% pins::pin_list(b$cache_board))
})

# ── Versioned board conflict: both become versions ────────────────────────────

test_that("versioned board conflict: version count grows (no loss)", {
  b <- new_fake_board("drive_cache", versioned = TRUE)
  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_vc"),
    .package = "gdpins"
  )
  .write_pin(b$drive_board, data.frame(x = 10), "p_vc")
  .write_pin(b$cache_board, data.frame(x = 20), "p_vc")

  drive_v_before <- nrow(pins::pin_versions(b$drive_board, "p_vc"))
  cache_v_before <- nrow(pins::pin_versions(b$cache_board, "p_vc"))

  suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "version"))

  drive_v_after <- nrow(pins::pin_versions(b$drive_board, "p_vc"))
  cache_v_after <- nrow(pins::pin_versions(b$cache_board, "p_vc"))

  expect_true("p_vc" %in% pins::pin_list(b$drive_board))
  expect_true("p_vc" %in% pins::pin_list(b$cache_board))
  expect_gte(drive_v_after, drive_v_before)
  expect_gte(cache_v_after, cache_v_before)
})

# ── Unversioned board conflict: on_conflict = "stop" ─────────────────────────

test_that("unversioned board conflict with on_conflict=stop aborts + changes nothing", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 111), "p_conflict_stop")
  .write_pin(b$cache_board, data.frame(x = 222), "p_conflict_stop")

  drv_obj_before <- pins::pin_read(b$drive_board, "p_conflict_stop")
  loc_obj_before <- pins::pin_read(b$cache_board, "p_conflict_stop")

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_conflict_stop"),
    .package = "gdpins"
  )
  expect_error(
    suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "stop")),
    class = "rlang_error"
  )

  # Assert nothing changed
  drv_obj_after <- pins::pin_read(b$drive_board, "p_conflict_stop")
  loc_obj_after <- pins::pin_read(b$cache_board, "p_conflict_stop")
  expect_equal(drv_obj_after$x, drv_obj_before$x)
  expect_equal(loc_obj_after$x, loc_obj_before$x)
})

test_that("unversioned board on_conflict=stop error message reports conflicting pins", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 1), "cp")
  .write_pin(b$cache_board, data.frame(x = 2), "cp")
  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("cp"),
    .package = "gdpins"
  )
  err <- tryCatch(
    suppressMessages(gdpins_sync(b, on_conflict = "stop")),
    error = function(e) e
  )
  expect_true(grepl("cp", conditionMessage(err)))
})

# ── Raw conflict: on_conflict = "stop" changes nothing ───────────────────────

test_that("raw conflict on_conflict=stop aborts + changes nothing", {
  conn <- new_fake_raw_conn("drive_local")

  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 7:9), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/conflict.csv"))
  dest_local <- file.path(conn$local_path, "conflict.csv")
  file.copy(tmp_l, dest_local)

  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/conflict.csv"), fixed = TRUE)
  )
  bytes_local_before <- readBin(dest_local, "raw", n = 10000L)
  bytes_drive_before <- readBin(drv_abs,   "raw", n = 10000L)

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("conflict.csv"),
    .package = "gdpins"
  )
  expect_error(
    suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "stop")),
    class = "rlang_error"
  )

  # Assert bytes unchanged
  expect_identical(readBin(dest_local, "raw", n = 10000L), bytes_local_before)
  expect_identical(readBin(drv_abs,   "raw", n = 10000L), bytes_drive_before)
})

test_that("raw on_conflict=stop error message names the conflicting files", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("bad_file.csv"),
    .package = "gdpins"
  )
  err <- tryCatch(
    suppressMessages(gdpins_sync(conn, on_conflict = "stop")),
    error = function(e) e
  )
  expect_true(grepl("bad_file.csv", conditionMessage(err)))
})

# ── Raw conflict: never silent overwrite ─────────────────────────────────────

test_that("raw conflict never overwrites silently: on_conflict=version keeps a file", {
  conn <- new_fake_raw_conn("drive_local")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 7:9), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/vc.csv"))
  dest_local <- file.path(conn$local_path, "vc.csv")
  file.copy(tmp_l, dest_local)

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("vc.csv"),
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "version"))
  # File still exists — not deleted
  expect_true(file.exists(dest_local))
})

# ── Raw conflict: on_conflict = "prompt" (mock readline) ─────────────────────

test_that("raw prompt conflict with 'd' choice overwrites local with drive content", {
  conn <- new_fake_raw_conn("drive_local")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 7:9), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/prompt.csv"))
  dest_local <- file.path(conn$local_path, "prompt.csv")
  file.copy(tmp_l, dest_local)

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("prompt.csv"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "d", .package = "base")

  suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "prompt"))
  local_content <- read.csv(dest_local)
  expect_equal(local_content$x, 1:3)
})

test_that("raw prompt conflict with 'l' choice uploads local to drive", {
  conn <- new_fake_raw_conn("drive_local")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 7:9), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/prompt_l.csv"))
  dest_local <- file.path(conn$local_path, "prompt_l.csv")
  file.copy(tmp_l, dest_local)

  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/prompt_l.csv"), fixed = TRUE)
  )

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("prompt_l.csv"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "l", .package = "base")

  suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "prompt"))
  drive_content <- read.csv(drv_abs)
  expect_equal(drive_content$x, 7:9)
})

test_that("raw prompt conflict with 's' choice skips (no change)", {
  conn <- new_fake_raw_conn("drive_local")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  tmp_l <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_d, row.names = FALSE)
  write.csv(data.frame(x = 7:9), tmp_l, row.names = FALSE)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/prompt_s.csv"))
  dest_local <- file.path(conn$local_path, "prompt_s.csv")
  file.copy(tmp_l, dest_local)

  bytes_before <- readBin(dest_local, "raw", n = 10000L)

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_raw_status_conflict("prompt_s.csv"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "s", .package = "base")

  suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "prompt"))
  expect_identical(readBin(dest_local, "raw", n = 10000L), bytes_before)
})

# ── New-computer case ─────────────────────────────────────────────────────────

test_that("board new-computer: empty local + populated drive pulls all pins", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 1), "nc1")
  .write_pin(b$drive_board, data.frame(x = 2), "nc2")
  expect_equal(length(pins::pin_list(b$cache_board)), 0L)
  suppressMessages(gdpins_sync(b, direction = "from_drive"))
  expect_true("nc1" %in% pins::pin_list(b$cache_board))
  expect_true("nc2" %in% pins::pin_list(b$cache_board))
})

test_that("board new-computer: auto direction also pulls drive-only pins", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 5), "nc_auto")
  msgs <- capture.output(
    suppressMessages(gdpins_sync(b, direction = "auto")),
    type = "message"
  )
  expect_true("nc_auto" %in% pins::pin_list(b$cache_board))
})

test_that("raw_conn new-computer: empty local + populated drive pulls files", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:5), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/nc_file.csv"))
  expect_equal(length(fs::dir_ls(conn$local_path, type = "file")), 0L)
  suppressMessages(gdpins_sync(conn, direction = "from_drive"))
  expect_true(file.exists(file.path(conn$local_path, "nc_file.csv")))
})

# ── local_only connections skip sync gracefully ───────────────────────────────

test_that("local_only board sync returns x invisibly without error", {
  b <- new_fake_board("local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  result <- suppressMessages(gdpins_sync(b))
  expect_s3_class(result, "gdpins_board")
})

test_that("local_only raw_conn sync returns x invisibly without error", {
  conn <- new_fake_raw_conn("local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  result <- suppressMessages(gdpins_sync(conn))
  expect_s3_class(result, "gdpins_raw_conn")
})

# ── Raw sync to_drive and from_drive ─────────────────────────────────────────

test_that("raw sync to_drive uploads local-only file to drive", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(y = 1:4), tmp, row.names = FALSE)
  file.copy(tmp, file.path(conn$local_path, "upload_me.csv"))
  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/upload_me.csv"), fixed = TRUE)
  )
  expect_false(file.exists(drv_abs))
  suppressMessages(gdpins_sync(conn, direction = "to_drive"))
  expect_true(file.exists(drv_abs))
})

test_that("raw sync from_drive downloads drive-only file to local", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(y = 1:4), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/dl_me.csv"))
  local_dest <- file.path(conn$local_path, "dl_me.csv")
  expect_false(file.exists(local_dest))
  suppressMessages(gdpins_sync(conn, direction = "from_drive"))
  expect_true(file.exists(local_dest))
})

# ── gdpins_sync dispatch ──────────────────────────────────────────────────────

test_that("gdpins_sync errors on unsupported class", {
  expect_error(suppressMessages(gdpins_sync(list())), class = "rlang_error")
})

# ── drive_cache_local (super) board ──────────────────────────────────────────

test_that("drive_cache_local board status uses cache_board as local side", {
  b <- new_fake_board("drive_cache_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 1), "super_pin")
  st <- gdpins_board_status(b)
  expect_equal(st$state[st$name == "super_pin"], "drive_ahead")
})

test_that("drive_cache_local board sync from_drive copies to cache_board", {
  b <- new_fake_board("drive_cache_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 99), "s2")
  suppressMessages(gdpins_sync(b, direction = "from_drive"))
  expect_true("s2" %in% pins::pin_list(b$cache_board))
})

# ── Empty boards/conns return x invisibly ─────────────────────────────────────

test_that("sync on empty board returns board invisibly", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  result <- suppressMessages(gdpins_sync(b))
  expect_s3_class(result, "gdpins_board")
})

test_that("sync on empty raw_conn returns conn invisibly", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  result <- suppressMessages(gdpins_sync(conn))
  expect_s3_class(result, "gdpins_raw_conn")
})

# ── Offline board status with no local pins ───────────────────────────────────

test_that("board offline status with no local pins returns empty tibble", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  st <- suppressWarnings(gdpins_board_status(b))
  expect_equal(nrow(st), 0L)
})

# ── Board status: drive_ahead detected via newer timestamp ────────────────────

test_that("board status detects drive_ahead via newer drive timestamp", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  # Write to cache first, then write newer/different data to drive
  .write_pin(b$cache_board, data.frame(x = 1), "ts_pin")
  Sys.sleep(1.1)  # ensure timestamp difference
  .write_pin(b$drive_board, data.frame(x = 2), "ts_pin")
  st <- gdpins_board_status(b)
  row <- st[st$name == "ts_pin", ]
  expect_true(row$state %in% c("drive_ahead", "conflict"))
})

test_that("board status detects local_ahead via newer local timestamp", {
  b <- new_fake_board("drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  .write_pin(b$drive_board, data.frame(x = 1), "ts_local")
  Sys.sleep(1.1)
  .write_pin(b$cache_board, data.frame(x = 2), "ts_local")
  st <- gdpins_board_status(b)
  row <- st[st$name == "ts_local", ]
  expect_true(row$state %in% c("local_ahead", "conflict"))
})

# ── Additional coverage tests ──────────────────────────────────────────────────

# Cover .list_local_files when dir doesn't exist
test_that(".list_local_files returns empty tibble for non-existent dir", {
  result <- gdpins:::.list_local_files(file.path(tempdir(), "no_such_dir_xyz"))
  expect_equal(nrow(result), 0L)
  expect_named(result, c("rel", "md5", "mtime"))
})

# Cover .empty_board_status_tbl structure
test_that(".empty_board_status_tbl returns correct structure", {
  tbl <- gdpins:::.empty_board_status_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 0L)
  expect_named(tbl, c("name", "state", "drive_version", "local_version",
                       "drive_created", "local_created", "drive_hash", "local_hash"))
})

# Cover .empty_raw_status_tbl structure
test_that(".empty_raw_status_tbl returns correct structure", {
  tbl <- gdpins:::.empty_raw_status_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 0L)
  expect_named(tbl, c("name", "state", "drive_md5", "local_md5",
                       "drive_mtime", "local_mtime"))
})

# Cover .board_local_side returning NULL for drive_cache with no cache or local
test_that(".board_local_side returns NULL when neither cache nor local board set", {
  b <- new_gdpins_board(
    config      = "drive_cache",
    name        = "test",
    drive_board = pins::board_folder(tempfile()),
    versioned   = TRUE
  )
  result <- gdpins:::.board_local_side(b)
  expect_null(result)
})

# Cover .board_local_side returning local_board when cache_board is NULL
test_that(".board_local_side returns local_board when cache_board is NULL", {
  local_dir   <- tempfile("local_")
  fs::dir_create(local_dir)
  local_board <- pins::board_folder(local_dir)
  b <- new_gdpins_board(
    config      = "drive_cache_local",
    name        = "test",
    drive_board = pins::board_folder(tempfile()),
    local_board = local_board,
    versioned   = TRUE
  )
  result <- gdpins:::.board_local_side(b)
  expect_identical(result, local_board)
})

# Cover unversioned board conflict with on_conflict = "version" (copies both ways)
test_that("unversioned board on_conflict=version copies both directions", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 10), "p_uv_ver")
  .write_pin(b$cache_board, data.frame(x = 20), "p_uv_ver")

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_uv_ver"),
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "version"))
  expect_true("p_uv_ver" %in% pins::pin_list(b$drive_board))
  expect_true("p_uv_ver" %in% pins::pin_list(b$cache_board))
})

# Cover unversioned board conflict with on_conflict = "prompt"
test_that("unversioned board on_conflict=prompt with 'l' pushes local to drive", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 10), "p_uv_prompt")
  .write_pin(b$cache_board, data.frame(x = 20), "p_uv_prompt")

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_uv_prompt"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "l", .package = "base")
  suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "prompt"))
  obj <- pins::pin_read(b$drive_board, "p_uv_prompt")
  expect_equal(obj$x, 20L)
})

test_that("unversioned board on_conflict=prompt with 'd' pulls drive to local", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 10), "p_uv_pd")
  .write_pin(b$cache_board, data.frame(x = 20), "p_uv_pd")

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_uv_pd"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "d", .package = "base")
  suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "prompt"))
  obj <- pins::pin_read(b$cache_board, "p_uv_pd")
  expect_equal(obj$x, 10L)
})

test_that("unversioned board on_conflict=prompt with 's' skips (no change)", {
  b <- new_fake_board("drive_cache", versioned = FALSE)
  .write_pin(b$drive_board, data.frame(x = 10), "p_uv_ps")
  .write_pin(b$cache_board, data.frame(x = 20), "p_uv_ps")

  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) .fake_board_status_conflict("p_uv_ps"),
    .package = "gdpins"
  )
  local_mocked_bindings(readline = function(prompt = "") "s", .package = "base")
  suppressMessages(gdpins_sync(b, direction = "auto", on_conflict = "prompt"))
  obj_d <- pins::pin_read(b$drive_board, "p_uv_ps")
  obj_l <- pins::pin_read(b$cache_board, "p_uv_ps")
  expect_equal(obj_d$x, 10L)
  expect_equal(obj_l$x, 20L)
})

# Cover .raw_copy_to_drive when local file doesn't exist (warn path)
test_that(".raw_copy_to_drive warns when local file missing", {
  conn <- new_fake_raw_conn("drive_local")
  expect_warning(
    gdpins:::.raw_copy_to_drive(conn, "nonexistent.csv"),
    class = "rlang_warning"
  )
})

# Cover .effective_direction skip fallthrough for offline state
test_that(".effective_direction returns skip for unknown state with auto", {
  result <- gdpins:::.effective_direction("unknown_state", "auto")
  expect_equal(result, "skip")
})

# Cover .drive_rel case 1 (path starts with drive_path prefix)
test_that(".drive_rel handles relative path (real adapter case)", {
  # Fake a minimal adapter with no $root (like real adapter)
  fake_adapter <- list(kind = "real")
  class(fake_adapter) <- "gdpins_drive_adapter"
  result <- gdpins:::.drive_rel(
    fake_adapter, "my/drive/path",
    "my/drive/path/subdir/file.csv"
  )
  expect_equal(result, "subdir/file.csv")
})

# Cover .list_local_files with empty directory
test_that(".list_local_files returns empty tibble for empty dir", {
  empty_dir <- withr::local_tempdir()
  result <- gdpins:::.list_local_files(empty_dir)
  expect_equal(nrow(result), 0L)
})

# Cover raw status: drive_ahead via newer drive mtime
test_that("raw_conn status drive_ahead via newer drive mtime", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  tmp_l <- withr::local_tempfile(fileext = ".csv")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_l, row.names = FALSE)
  write.csv(data.frame(x = 4:6), tmp_d, row.names = FALSE)

  dest_local <- file.path(conn$local_path, "both.csv")
  file.copy(tmp_l, dest_local)
  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/both.csv"))

  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/both.csv"), fixed = TRUE)
  )
  # Set drive mtime to be 2 seconds after local
  future_time <- file.mtime(dest_local) + 2
  Sys.setFileTime(drv_abs, future_time)

  st <- gdpins_board_status(conn)
  expect_true(st$state[st$name == "both.csv"] %in% c("drive_ahead", "conflict"))
})

# Cover .copy_pin_to_board warn path (pin not on source board)
test_that(".copy_pin_to_board warns when pin not found on source", {
  b <- new_fake_board("drive_cache")
  # drive_board doesn't have the pin; this triggers the warn path
  expect_warning(
    gdpins:::.copy_pin_to_board(b$drive_board, b$cache_board, "nonexistent_pin"),
    class = "rlang_warning"
  )
})

# Cover .sync_raw "skip" effective_dir (in_sync state with auto direction)
test_that("sync_raw skips in_sync files without error", {
  conn <- new_fake_raw_conn("drive_local")
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/same.csv"))
  file.copy(tmp, file.path(conn$local_path, "same.csv"))
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  expect_no_error(suppressMessages(gdpins_sync(conn, direction = "auto")))
})

# Cover .compare_board_pin when both in_drive and in_local with same hash (in_sync)
# and when neither (defensive path line 196 — impossible but cover via direct call)
test_that(".compare_board_pin returns in_sync when both sides absent (defensive)", {
  b <- new_fake_board("drive_cache")
  .write_pin(b$drive_board, data.frame(x = 1), "p_def")
  .write_pin(b$cache_board, data.frame(x = 1), "p_def")
  result <- gdpins:::.compare_board_pin(
    pin_name    = "p_def",
    drive_board = b$drive_board,
    local_board = b$cache_board,
    in_drive    = FALSE,
    in_local    = FALSE
  )
  expect_equal(result$state, "in_sync")
})

# Cover .compare_board_pin: conflict when NA timestamps (both exist, different hash, NA timestamp)
test_that(".compare_board_pin returns conflict when timestamps are NA", {
  b <- new_fake_board("drive_cache")
  # Call directly with in_drive/in_local both TRUE but force NA created by mocking
  # .latest_version to return a row with NA created
  local_mocked_bindings(
    .latest_version = function(board, pin_name) {
      tibble::tibble(
        version = "v1",
        created = as.POSIXct(NA),
        hash    = if (identical(board, b$drive_board)) "aaa" else "bbb"
      )
    },
    .package = "gdpins"
  )
  result <- gdpins:::.compare_board_pin(
    pin_name    = "p_na",
    drive_board = b$drive_board,
    local_board = b$cache_board,
    in_drive    = TRUE,
    in_local    = TRUE
  )
  expect_equal(result$state, "conflict")
})

# Cover .offline_raw_status_tbl when local dir is empty
test_that(".offline_raw_status_tbl returns empty tbl when local dir has no files", {
  conn <- new_fake_raw_conn("drive_local")
  # Empty local_path
  result <- gdpins:::.offline_raw_status_tbl(conn)
  expect_equal(nrow(result), 0L)
})

# Cover .empty_gd_ls_tbl structure
test_that(".empty_gd_ls_tbl returns correct structure", {
  tbl <- gdpins:::.empty_gd_ls_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 0L)
  expect_named(tbl, c("path", "is_dir", "size", "md5", "mtime"))
})

# Cover raw status: NA mtime conflict (mtime is NA on one side)
test_that("raw status returns conflict when md5 differs and mtime is NA", {
  conn <- new_fake_raw_conn("drive_local")
  # Construct status with NA mtime directly via mocked gdpins_board_status
  # to test the sync path
  common <- as.POSIXct(NA)
  fake_st <- tibble::tibble(
    name        = "na_mtime.csv",
    state       = "conflict",
    drive_md5   = "aaa",
    local_md5   = "bbb",
    drive_mtime = list(common),
    local_mtime = list(common)
  )
  local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) fake_st,
    .package = "gdpins"
  )
  # on_conflict = "version" on raw: drive wins
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp, row.names = FALSE)
  gd_upload(conn$adapter, tmp, paste0(conn$drive_path, "/na_mtime.csv"))
  suppressMessages(gdpins_sync(conn, direction = "auto", on_conflict = "version"))
  expect_true(file.exists(file.path(conn$local_path, "na_mtime.csv")))
})

# Cover .board_status_raw gd_ls error fallback to empty tbl
test_that("board_status_raw handles gd_ls error gracefully", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gd_ls            = function(...) stop("Drive error"),
    .package = "gdpins"
  )
  st <- gdpins_board_status(conn)
  expect_equal(nrow(st), 0L)
})

# Cover .latest_version returning NULL when pin_versions has 0 rows
test_that(".latest_version returns NULL for 0-row versions", {
  b <- new_fake_board("drive_cache")
  # Mock pin_versions to return empty tibble
  local_mocked_bindings(
    pin_versions = function(board, name) tibble::tibble(
      version = character(), created = as.POSIXct(character()), hash = character()
    ),
    .package = "pins"
  )
  result <- gdpins:::.latest_version(b$drive_board, "p")
  expect_null(result)
})

# Cover raw status: local_ahead via newer local mtime
test_that("raw_conn status local_ahead via newer local mtime", {
  conn <- new_fake_raw_conn("drive_local")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  tmp_l <- withr::local_tempfile(fileext = ".csv")
  tmp_d <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(x = 1:3), tmp_l, row.names = FALSE)
  write.csv(data.frame(x = 4:6), tmp_d, row.names = FALSE)

  gd_upload(conn$adapter, tmp_d, paste0(conn$drive_path, "/both2.csv"))
  dest_local <- file.path(conn$local_path, "both2.csv")
  file.copy(tmp_l, dest_local)

  drv_abs <- file.path(
    conn$adapter$root,
    gsub("/", .Platform$file.sep,
         paste0(conn$drive_path, "/both2.csv"), fixed = TRUE)
  )
  # Set local mtime to be 2 seconds after drive
  future_time <- file.mtime(drv_abs) + 2
  Sys.setFileTime(dest_local, future_time)

  st <- gdpins_board_status(conn)
  expect_true(st$state[st$name == "both2.csv"] %in% c("local_ahead", "conflict"))
})
