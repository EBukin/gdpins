# test-prune.R — TDD tests for R/prune.R (WS6)
# Uses new_fake_board(versioned=TRUE); seeds versions directly via
# repeated pins::pin_write() calls on drive_board and local_board.
# No network. No dependency on WS3 verbs.

# ── Helpers ───────────────────────────────────────────────────────────────────

# Seed n versions of `name` into whichever of drive_board / local_board exist.
seed_versions <- function(board, name, n) {
  for (i in seq_len(n)) {
    if (!is.null(board$drive_board)) {
      pins::pin_write(board$drive_board, data.frame(v = i), name)
    }
    if (!is.null(board$local_board)) {
      pins::pin_write(board$local_board, data.frame(v = i), name)
    }
  }
  invisible(board)
}

# Count versions on a given sub-board
count_versions <- function(sub_board, name) {
  nrow(pins::pin_versions(sub_board, name))
}

# Version ids a prune plan removes (or would remove) on one side, optionally
# for one pin only.
removed <- function(plan, side = "drive", pin = NULL) {
  keep_row <- plan$side == side & plan$action == "remove"
  if (!is.null(pin)) keep_row <- keep_row & plan$name == pin
  plan$version[keep_row]
}

# ── dry_run (default) ─────────────────────────────────────────────────────────

test_that("dry_run shows plan and changes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = TRUE)

  # Returns a plan with the 2 old versions that WOULD be removed on each side
  expect_s3_class(result, "tbl_df")
  expect_length(removed(result, "drive"), 2L)
  expect_length(removed(result, "local"), 2L)

  # Nothing was actually removed — still 3 on both boards
  expect_equal(count_versions(board$drive_board, "mypin"), 3L)
  expect_equal(count_versions(board$local_board, "mypin"), 3L)
})

test_that("dry_run=TRUE is the default", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 2)

  # Call without specifying dry_run -> should default to TRUE (no removal)
  gdpins_prune_pin_versions(board, "mypin", keep = 1)

  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$local_board, "mypin"), 2L)
})

test_that("dry_run=FALSE with nothing to prune returns a 0-row plan", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 1)  # only 1 version, keep=1 -> nothing to remove

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  expect_equal(nrow(result), 0L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

# ── actual prune — keeps newest keep, removes older ──────────────────────────

test_that("removes old versions from Drive and cache", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 4)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 2, dry_run = FALSE
  )

  # 2 old versions removed
  expect_length(removed(result), 2L)
  # Drive and cache each now have 2 versions
  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$local_board, "mypin"), 2L)
})

test_that("returns the removed version labels", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v <- pins::pin_versions(board$drive_board, "mypin")$version
  # Newest-last: all_v[3] is newest; all_v[1], all_v[2] are old
  old_expected <- sort(all_v[seq_len(length(all_v) - 1L)])

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE
  )

  expect_setequal(removed(result), old_expected)
})

test_that("keeps the newest versions after pruning", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 4)

  all_v_before <- pins::pin_versions(board$drive_board, "mypin")$version

  gdpins_prune_pin_versions(board, "mypin", keep = 2, dry_run = FALSE)

  remaining_v <- pins::pin_versions(board$drive_board, "mypin")$version
  # The 2 remaining should be the 2 newest (last 2 in ascending-sorted list)
  expect_setequal(
    remaining_v,
    tail(sort(all_v_before), 2L)
  )
})

test_that("keep >= n_versions removes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 5, dry_run = FALSE
  )

  expect_equal(nrow(result), 0L)
  expect_equal(count_versions(board$drive_board, "mypin"), 3L)
})

# ── TRASH not hard-delete ─────────────────────────────────────────────────────

test_that("trashes Drive versions into adapter trash store (recoverable)", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v_before <- pins::pin_versions(board$drive_board, "mypin")$version
  old_v <- head(sort(all_v_before), 2L)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  adapter <- board$adapter
  trash_keys <- names(adapter$state$trash)

  # Each trashed version should appear in the adapter's trash store
  for (v in old_v) {
    expected_path <- paste0(board$drive_path, "/mypin/", v)
    expect_true(
      any(startsWith(trash_keys, expected_path)),
      info = paste("Expected trash key for version:", v)
    )
  }
})

test_that("trashed dirs are NOT hard-deleted — remain in trash store on disk", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v <- pins::pin_versions(board$drive_board, "mypin")$version
  old_v <- head(sort(all_v), 2L)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Trash store entries must physically exist on disk (moved, not deleted)
  for (k in names(board$adapter$state$trash)) {
    trash_entry <- board$adapter$state$trash[[k]]
    expect_true(
      file.exists(trash_entry),
      info = paste("Trashed item must still exist on disk:", trash_entry)
    )
  }
})

# ── cache removal (local fs unlink, not trash) ────────────────────────────────

test_that("removes old versions from cache dir", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Cache should now have only 1 version
  expect_equal(count_versions(board$local_board, "mypin"), 1L)
})

# ── threshold guard ───────────────────────────────────────────────────────────

test_that("aborts when removal > threshold and force=FALSE", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)  # 14 removals > threshold=10

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing was removed
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

test_that("proceeds when force=TRUE even above threshold", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = TRUE
  )

  expect_length(removed(result), 14L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("allows removal at exactly threshold (no force needed)", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 11)  # 11 versions, keep=1 -> 10 removals == threshold

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_length(removed(result), 10L)
  expect_length(removed(result, "local"), 10L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("threshold abort leaves Drive and cache unchanged", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    )
  )

  # Both boards still untouched
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
  expect_equal(count_versions(board$local_board, "mypin"), 15L)
})

# ── dry_run + threshold interaction ──────────────────────────────────────────

test_that("dry_run skips threshold check entirely", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  # dry_run=TRUE should NOT raise error even when > threshold
  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = TRUE,
    threshold = 10, force = FALSE
  )

  # Shows what would be removed
  expect_length(removed(result), 14L)
  # Removes nothing
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

# ── board-level prune ─────────────────────────────────────────────────────────

test_that("gdpins_prune_board_versions prunes all pins in the board", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "pin_a", 4)
  seed_versions(board, "pin_b", 3)

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE
  )

  expect_setequal(unique(result$name), c("pin_a", "pin_b"))
  expect_length(removed(result, pin = "pin_a"), 3L)
  expect_length(removed(result, pin = "pin_b"), 2L)
  expect_length(removed(result, "local", pin = "pin_a"), 3L)

  expect_equal(count_versions(board$drive_board, "pin_a"), 1L)
  expect_equal(count_versions(board$drive_board, "pin_b"), 1L)
  expect_equal(count_versions(board$local_board, "pin_a"), 1L)
  expect_equal(count_versions(board$local_board, "pin_b"), 1L)
})

test_that("gdpins_prune_board_versions dry_run shows plan and changes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "alpha", 3)
  seed_versions(board, "beta", 2)

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = TRUE)

  expect_setequal(unique(result$name), c("alpha", "beta"))
  # Nothing removed
  expect_equal(count_versions(board$drive_board, "alpha"), 3L)
  expect_equal(count_versions(board$drive_board, "beta"), 2L)
})

test_that("gdpins_prune_board_versions returns one plan tibble", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "p1", 2)

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("name", "version", "side", "hash", "action"))
  expect_equal(unique(result$name), "p1")
})

test_that("gdpins_prune_board_versions threshold blocks oversized per-pin removal", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big",    15)  # 14 removals > threshold=10
  seed_versions(board, "small",   3)  # 2 removals <= threshold=10

  expect_error(
    gdpins_prune_board_versions(
      board, keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing removed from either pin
  expect_equal(count_versions(board$drive_board, "big"),   15L)
  expect_equal(count_versions(board$drive_board, "small"),  3L)
})

test_that("gdpins_prune_board_versions force=TRUE bypasses threshold for all pins", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big",   15)
  seed_versions(board, "small",  3)

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE,
    threshold = 10, force = TRUE
  )

  expect_equal(count_versions(board$drive_board, "big"),   1L)
  expect_equal(count_versions(board$drive_board, "small"), 1L)
})

test_that("gdpins_prune_board_versions works on local_only board (no adapter)", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  pins::pin_write(board$local_board, data.frame(v = 1), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 2), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 3), "lpin")

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_equal(unique(result$name), "lpin")
  expect_length(removed(result, "local", pin = "lpin"), 2L)
  expect_equal(count_versions(board$local_board, "lpin"), 1L)
})

# ── local_only board single-pin prune ─────────────────────────────────────────

test_that("gdpins_prune_pin_versions works on local_only board", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  pins::pin_write(board$local_board, data.frame(v = 1), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 2), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 3), "lpin")

  result <- gdpins_prune_pin_versions(
    board, "lpin", keep = 1, dry_run = FALSE
  )

  expect_length(removed(result, "local"), 2L)
  expect_equal(count_versions(board$local_board, "lpin"), 1L)
})

# ── return value invisibility ─────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions returns invisibly", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  expect_invisible(
    gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)
  )
})

test_that("gdpins_prune_board_versions returns invisibly", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  expect_invisible(
    gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)
  )
})

# ── input validation ──────────────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions errors on non-gdpins_board", {
  expect_error(
    gdpins_prune_pin_versions("not_a_board", "mypin"),
    regexp = "gdpins_board"
  )
})

test_that("gdpins_prune_board_versions errors on non-gdpins_board", {
  expect_error(
    gdpins_prune_board_versions("not_a_board"),
    regexp = "gdpins_board"
  )
})

test_that("gdpins_prune_pin_versions errors when keep < 1", {
  board <- new_fake_board(versioned = TRUE)
  expect_error(
    gdpins_prune_pin_versions(board, "mypin", keep = 0),
    regexp = "keep"
  )
})

test_that("gdpins_prune_board_versions errors when keep < 1", {
  board <- new_fake_board(versioned = TRUE)
  expect_error(
    gdpins_prune_board_versions(board, keep = 0),
    regexp = "keep"
  )
})

# ── drive_only config ──────────────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions on drive_only trashes Drive versions, no local board", {
  board <- new_fake_board(config = "drive_only", versioned = TRUE)
  expect_null(board$local_board)
  seed_versions(board, "mypin", 3)

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  expect_length(removed(result), 2L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)

  # Two old versions must appear in the adapter's trash store
  trash_keys <- names(board$adapter$state$trash)
  expect_true(length(trash_keys) >= 2L)
})

test_that("gdpins_prune_pin_versions on drive_only does not error with no local board", {
  board <- new_fake_board(config = "drive_only", versioned = TRUE)
  seed_versions(board, "mypin", 2)

  expect_no_error(
    gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)
  )
})

test_that("gdpins_prune_pin_versions threshold guard enforced on drive_only", {
  board <- new_fake_board(config = "drive_only", versioned = TRUE)
  seed_versions(board, "mypin", 15)  # 14 removals > threshold=10

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

test_that("gdpins_prune_pin_versions force=TRUE bypasses threshold on drive_only", {
  board <- new_fake_board(config = "drive_only", versioned = TRUE)
  seed_versions(board, "mypin", 15)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = TRUE
  )

  expect_length(removed(result), 14L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

# ── version-label skew between Drive and local ──────────────────────────────────

test_that("prune keeps newest `keep` per board when Drive/local version labels differ", {
  board <- new_fake_board(config = "drive_cache", versioned = TRUE)

  # Write Drive then local with a timestamp gap so the same logical version
  # gets different version labels on each board.
  pins::pin_write(board$drive_board, data.frame(v = 1), "mypin")
  Sys.sleep(1.1)
  pins::pin_write(board$local_board, data.frame(v = 1), "mypin")
  pins::pin_write(board$drive_board, data.frame(v = 2), "mypin")
  pins::pin_write(board$local_board, data.frame(v = 2), "mypin")

  drive_v_before <- pins::pin_versions(board$drive_board, "mypin")$version
  local_v_before  <- pins::pin_versions(board$local_board,  "mypin")$version
  expect_false(identical(sort(drive_v_before), sort(local_v_before)))

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Each board independently kept its own newest version label.
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
  expect_equal(count_versions(board$local_board,  "mypin"), 1L)
  expect_equal(
    pins::pin_versions(board$drive_board, "mypin")$version,
    tail(sort(drive_v_before), 1L)
  )
  expect_equal(
    pins::pin_versions(board$local_board, "mypin")$version,
    tail(sort(local_v_before), 1L)
  )
})

# ── [V6] verifier additions ───────────────────────────────────────────────────

test_that("[V6] explicit drive_cache config removes old versions from BOTH Drive and local_board", {
  board <- new_fake_board(config = "drive_cache", versioned = TRUE)
  seed_versions(board, "mypin", 4)

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 2, dry_run = FALSE)

  expect_length(removed(result), 2L)
  expect_length(removed(result, "local"), 2L)
  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$local_board, "mypin"), 2L)
})

test_that("[V6] gdpins_prune_board_versions works on drive_only board (no local_board)", {
  board <- new_fake_board(config = "drive_only", versioned = TRUE)
  expect_null(board$local_board)
  for (i in 1:3) pins::pin_write(board$drive_board, data.frame(v = i), "p1")
  for (i in 1:2) pins::pin_write(board$drive_board, data.frame(v = i), "p2")

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_setequal(unique(result$name), c("p1", "p2"))
  expect_length(removed(result, pin = "p1"), 2L)
  expect_length(removed(result, pin = "p2"), 1L)
  expect_false(any(result$side == "local"))
  expect_equal(count_versions(board$drive_board, "p1"), 1L)
  expect_equal(count_versions(board$drive_board, "p2"), 1L)
})

test_that("[V6] keep given as a non-coercible string errors with the keep message", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 2)

  expect_error(
    suppressWarnings(
      gdpins_prune_pin_versions(board, "mypin", keep = "abc", dry_run = FALSE)
    ),
    regexp = "keep"
  )

  # Nothing removed
  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$local_board, "mypin"), 2L)
})

test_that("[V6] pruning a nonexistent pin name errors instead of silently no-op", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 2)

  expect_error(
    gdpins_prune_pin_versions(board, "doesnotexist", keep = 1, dry_run = FALSE)
  )
})

test_that("[V6] a vector `name` input errors rather than silently pruning only one", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "a", 2)
  seed_versions(board, "b", 2)

  expect_error(
    gdpins_prune_pin_versions(board, c("a", "b"), keep = 1, dry_run = FALSE)
  )

  # Neither pin was touched since the call errored before any removal
  expect_equal(count_versions(board$drive_board, "a"), 2L)
  expect_equal(count_versions(board$drive_board, "b"), 2L)
})

# ── empty board ───────────────────────────────────────────────────────────────

test_that("gdpins_prune_board_versions returns a 0-row plan for board with no pins", {
  board <- new_fake_board(versioned = TRUE)
  # Do not write any pins

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("name", "version", "side", "hash", "action"))
  expect_equal(nrow(result), 0L)
})

# ── interactive threshold prompt (mocked) ────────────────────────────────────

test_that("gdpins_prune_pin_versions interactive prompt 'y' proceeds", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  # Mock the package-level wrapper so interactive() appears TRUE
  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "y",
    .package              = "gdpins"
  )

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_length(removed(result), 14L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("gdpins_prune_pin_versions interactive prompt 'N' aborts", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "N",
    .package              = "gdpins"
  )

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing removed
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

test_that("gdpins_prune_board_versions interactive prompt 'y' proceeds", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "y",
    .package              = "gdpins"
  )

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_equal(count_versions(board$drive_board, "big"), 1L)
})

test_that("gdpins_prune_board_versions interactive prompt 'N' aborts", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "N",
    .package              = "gdpins"
  )

  expect_error(
    gdpins_prune_board_versions(
      board, keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  expect_equal(count_versions(board$drive_board, "big"), 15L)
})

# ── internal helper coverage ──────────────────────────────────────────────────

test_that(".prune_readline delegates to base readline", {
  # Mock base::readline to avoid interactive requirement
  local_mocked_bindings(
    readline = function(prompt) paste0("echo:", prompt),
    .package = "base"
  )
  result <- gdpins:::.prune_readline("test prompt")
  expect_identical(result, "echo:test prompt")
})

# ── H8: local-only versions are planned, counted and never lost ──────────────

# Version ids of a pin on a sub-board, oldest first.
version_ids <- function(sub_board, name) {
  pins::pin_versions(sub_board, name)$version
}

test_that("H8 dry run plans Drive and local removals in one tibble, unsynced newest absent", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board <- new_fake_board("drive_cache", versioned = TRUE)
  for (i in 1:3) {
    suppressMessages(gdpins_pin_write(board, data.frame(v = i), "p"))
    Sys.sleep(1.1)
  }
  pins::pin_write(board$local_board, data.frame(v = 4), "p")
  drive_v <- version_ids(board$drive_board, "p")
  local_v <- version_ids(board$local_board, "p")

  plan <- suppressMessages(
    gdpins_prune_pin_versions(board, "p", keep = 2, dry_run = TRUE)
  )

  expect_s3_class(plan, "tbl_df")
  expect_named(plan, c("name", "version", "side", "hash", "action"))
  expect_equal(nrow(plan), 3L)
  expect_true(all(plan$action == "remove"))
  expect_equal(plan$version[plan$side == "drive"], drive_v[1])
  expect_setequal(plan$version[plan$side == "local"], local_v[1:2])
  expect_false(local_v[4] %in% plan$version)
  expect_equal(count_versions(board$drive_board, "p"), 3L)
  expect_equal(count_versions(board$local_board, "p"), 4L)
})

test_that("H8 an unsynced local version older than the synced ones is kept", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board <- new_fake_board("drive_cache", versioned = TRUE)
  pins::pin_write(board$local_board, data.frame(v = 0), "p")
  v_old <- version_ids(board$local_board, "p")
  Sys.sleep(1.1)
  for (i in 1:3) {
    suppressMessages(gdpins_pin_write(board, data.frame(v = i), "p"))
    Sys.sleep(1.1)
  }
  # One parquet write per gdpins_pin_write(): both boards hold the same bytes.
  drive_hash <- pins::pin_versions(board$drive_board, "p")$hash
  local_hash <- pins::pin_versions(board$local_board, "p")$hash
  expect_true(all(drive_hash %in% local_hash))
  drive_v <- version_ids(board$drive_board, "p")
  local_v <- version_ids(board$local_board, "p")

  plan <- suppressMessages(gdpins_prune_pin_versions(
    board, "p", keep = 2, dry_run = FALSE, force = TRUE
  ))

  expect_no_error(pins::pin_read(board$local_board, "p", version = v_old))
  expect_setequal(version_ids(board$drive_board, "p"), drive_v[2:3])
  expect_setequal(version_ids(board$local_board, "p"), c(v_old, local_v[3:4]))
  expect_equal(plan$action[plan$version == v_old], "keep_unsynced")
  expect_equal(
    plan$version[plan$side == "local" & plan$action == "remove"],
    local_v[2]
  )
})

test_that("H8 threshold counts local removals, not only Drive removals", {
  board <- new_fake_board("drive_cache", versioned = TRUE)
  seed_versions(board, "p", 2)
  Sys.sleep(1.1)
  for (i in 1:4) pins::pin_write(board$local_board, data.frame(v = 10 + i), "p")
  expect_equal(count_versions(board$local_board, "p"), 6L)

  expect_error(
    suppressMessages(gdpins_prune_pin_versions(
      board, "p", keep = 1, dry_run = FALSE, threshold = 1, force = FALSE
    )),
    regexp = "force"
  )
  expect_equal(count_versions(board$local_board, "p"), 6L)
  expect_equal(count_versions(board$drive_board, "p"), 2L)
})

test_that("H8 board prune compares the total removal count with the threshold", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "a", 7)
  seed_versions(board, "b", 7)

  expect_error(
    suppressMessages(gdpins_prune_board_versions(
      board, keep = 1, dry_run = FALSE, threshold = 10, force = FALSE
    )),
    regexp = "force"
  )
  expect_equal(count_versions(board$drive_board, "a"), 7L)
  expect_equal(count_versions(board$local_board, "b"), 7L)
})

test_that("H8 an offline board never deletes versions it cannot check against Drive", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board <- new_fake_board("drive_cache", versioned = TRUE)
  suppressMessages(gdpins_pin_write(board, data.frame(v = 1), "p"))
  v1 <- version_ids(board$local_board, "p")
  offline <- suppressMessages(gdpins_go_offline(board))
  Sys.sleep(1.1)
  suppressMessages(gdpins_pin_write(offline, data.frame(v = 2), "p"))

  plan <- suppressMessages(gdpins_prune_pin_versions(
    offline, "p", keep = 1, dry_run = FALSE, force = TRUE
  ))

  expect_true(v1 %in% version_ids(offline$local_board, "p"))
  expect_equal(count_versions(offline$local_board, "p"), 2L)
  expect_equal(plan$action[plan$version == v1], "keep_unsynced")
})

test_that("H8 a local_only board still prunes every version beyond keep", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  for (i in 1:3) pins::pin_write(board$local_board, data.frame(v = i), "lpin")

  plan <- suppressMessages(
    gdpins_prune_pin_versions(board, "lpin", keep = 1, dry_run = FALSE)
  )

  expect_equal(nrow(plan), 2L)
  expect_true(all(plan$side == "local"))
  expect_true(all(plan$action == "remove"))
  expect_equal(count_versions(board$local_board, "lpin"), 1L)
})

test_that("H8 'no versions to remove' reports the real number present", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "p", 3)

  expect_message(
    gdpins_prune_pin_versions(board, "p", keep = 5),
    regexp = "3 present"
  )
})

test_that("H8 board prune handles a pin that exists on Drive only", {
  board <- new_fake_board("drive_cache", versioned = TRUE)
  for (i in 1:2) pins::pin_write(board$drive_board, data.frame(v = i), "donly")

  expect_no_error(
    plan <- suppressMessages(
      gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)
    )
  )
  expect_equal(sum(plan$name == "donly" & plan$side == "drive"), 1L)
  expect_equal(sum(plan$name == "donly" & plan$side == "local"), 0L)
  expect_equal(count_versions(board$drive_board, "donly"), 1L)
})
