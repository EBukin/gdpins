# test-validate.R -- pin names and raw file names must not escape the board /
# local_path (audit H1, H2).
#
# SAFETY: every test here builds its objects with new_sandboxed_board() /
# new_sandboxed_raw_conn() over a withr::local_tempdir(). Never use
# new_fake_board() / new_fake_raw_conn() with "." or "..": on unfixed code those
# names reach the session tempdir() itself.

bad_pin_names <- list(
  ".", "..", "a/b", "a\\b", ".hidden", "a\nb",
  NA_character_, character(0), c("a", "b"), ""
)

bad_raw_names <- list(
  "..", "a\\b", "a\nb", NA_character_, character(0), c("a.csv", "b.csv"), "",
  "C:/x.csv", "/x.csv", "../x.csv", "sub/../../x.csv", "./a.csv",
  "a/.. /x.csv", "a/... /x.csv"
)

show_name <- function(x) paste(deparse(x), collapse = "")

# ── H1: pin names ─────────────────────────────────────────────────────────────

test_that("pin_remove('..') errors and leaves the board's parent intact", {
  parent   <- withr::local_tempdir()
  board    <- new_sandboxed_board(parent, "local_only")
  sentinel <- file.path(parent, "sentinel.txt")
  writeLines("keep me", sentinel)
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  expect_error(gdpins_pin_remove(board, ".."), class = "gdpins_error_invalid_name")
  expect_true(file.exists(sentinel))
})

test_that("prune_pin_versions('..') errors and deletes no sibling of the board", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "local_only")
  aaa    <- file.path(parent, "20260101T000000Z-aaa")
  bbb    <- file.path(parent, "20260102T000000Z-bbb")
  fs::dir_create(c(aaa, bbb))
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  expect_error(
    suppressMessages(
      gdpins_prune_pin_versions(board, "..", keep = 1, dry_run = FALSE, force = TRUE)
    ),
    class = "gdpins_error_invalid_name"
  )
  expect_true(dir.exists(aaa))
  expect_true(dir.exists(bbb))
  expect_true(dir.exists(file.path(parent, "cache")))
})

pin_verbs <- list(
  gdpins_pin_write  = function(b, n) gdpins_pin_write(b, data.frame(x = 1), n),
  gdpins_pin_read   = function(b, n) gdpins_pin_read(b, n),
  gdpins_pin_path   = function(b, n) gdpins_pin_path(b, n),
  gdpins_pin_remove = function(b, n) gdpins_pin_remove(b, n),
  gdpins_prune_pin_versions = function(b, n) {
    gdpins_prune_pin_versions(b, n, keep = 1, dry_run = TRUE)
  }
)

for (verb in names(pin_verbs)) {
  for (nm in bad_pin_names) {
    lbl <- paste0(verb, "(board, ", show_name(nm), ")")
    test_that(paste(lbl, "is rejected before touching storage"), {
      local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
      parent <- withr::local_tempdir()
      board  <- new_sandboxed_board(parent, "local_only")
      before <- sandbox_listing(parent)

      expect_error(
        suppressMessages(pin_verbs[[verb]](board, nm)),
        class = "gdpins_error_invalid_name",
        label = lbl
      )
      expect_identical(sandbox_listing(parent), before, label = lbl)
    })
  }
}

test_that("scalar check keeps its 'non-empty character scalar' message", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "local_only")
  expect_error(gdpins_pin_read(board, ""), "non-empty character scalar")
  expect_error(gdpins_pin_remove(board, c("a", "b")), "non-empty character scalar")
})

test_that("ordinary pin names are still accepted", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")

  for (nm in c("my_pin", "pin-2024", "Quarterly.Report")) {
    gdpins_pin_write(board, data.frame(x = nchar(nm)), nm)
    expect_equal(gdpins_pin_read(board, nm)$x, nchar(nm), label = nm)
  }
})

test_that(".copy_pin_to_board() refuses a Drive-sourced '..'", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "drive_cache")

  expect_error(
    .copy_pin_to_board(board$drive_board, board$local_board, ".."),
    class = "gdpins_error_invalid_name"
  )
})

test_that("board status skips and warns on an unsafe Drive pin name", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "drive_cache")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  gdpins_pin_write(board, data.frame(x = 1), "ok")

  real_pin_list <- pins::pin_list
  drive_path    <- board$drive_board$path
  local_mocked_bindings(
    pin_list = function(board, ...) {
      out <- real_pin_list(board, ...)
      if (identical(board$path, drive_path)) c(out, "..") else out
    },
    .package = "pins"
  )

  expect_warning(
    status <- .board_status_board(board),
    class = "gdpins_warning_invalid_name"
  )
  expect_identical(status$name, "ok")
})

test_that("board prune skips and warns on an unsafe pin name", {
  parent <- withr::local_tempdir()
  board  <- new_sandboxed_board(parent, "local_only")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  gdpins_pin_write(board, data.frame(x = 1), "ok")

  real_pin_list <- pins::pin_list
  local_mocked_bindings(
    pin_list = function(board, ...) c(real_pin_list(board, ...), ".."),
    .package = "pins"
  )

  expect_warning(
    res <- suppressMessages(gdpins_prune_board_versions(board, dry_run = TRUE)),
    class = "gdpins_warning_invalid_name"
  )
  expect_identical(names(res), "ok")
})

# ── H2: raw file names ────────────────────────────────────────────────────────

test_that("raw_put_object('../sentinel.csv') errors and leaves the sentinel", {
  parent   <- withr::local_tempdir()
  conn     <- new_sandboxed_raw_conn(parent, "local_only")
  sentinel <- file.path(parent, "sentinel.csv")
  writeLines("original", sentinel)
  before <- readBin(sentinel, "raw", 1000L)

  expect_error(
    gdpins_raw_put_object(conn, mtcars, "../sentinel.csv"),
    class = "gdpins_error_invalid_name"
  )
  expect_identical(readBin(sentinel, "raw", 1000L), before)
})

raw_verbs <- list(
  gdpins_raw_put_object = function(c, n, src) gdpins_raw_put_object(c, mtcars, n),
  gdpins_raw_put_file   = function(c, n, src) gdpins_raw_put_file(c, src, n),
  gdpins_raw_remove     = function(c, n, src) gdpins_raw_remove(c, n),
  gdpins_raw_get        = function(c, n, src) gdpins_raw_get(c, n),
  gdpins_raw_path       = function(c, n, src) gdpins_raw_path(c, n)
)

for (verb in names(raw_verbs)) {
  for (nm in bad_raw_names) {
    lbl <- paste0(verb, "(conn, ", show_name(nm), ")")
    test_that(paste(lbl, "is rejected before touching storage"), {
      src_dir <- withr::local_tempdir()
      src     <- file.path(src_dir, "src.csv")
      writeLines("x\n1", src)
      parent <- withr::local_tempdir()
      conn   <- new_sandboxed_raw_conn(parent, "drive_local")
      # A file the escaping names could hit, so remove/get/path have a target.
      writeLines("y\n2", file.path(parent, "x.csv"))
      before <- sandbox_listing(parent)

      expect_error(
        raw_verbs[[verb]](conn, nm, src),
        class = "gdpins_error_invalid_name",
        label = lbl
      )
      expect_identical(sandbox_listing(parent), before, label = lbl)
      expect_identical(readLines(file.path(parent, "x.csv")), c("y", "2"), label = lbl)
    })
  }
}

test_that("ordinary raw names are still accepted", {
  parent <- withr::local_tempdir()
  conn   <- new_sandboxed_raw_conn(parent, "drive_local")
  df     <- data.frame(x = 1:3)

  for (nm in c("sub/a.csv", "a..b.csv", "my data (2024).csv",
               "report - final v2.csv", "a{bad}.csv")) {
    gdpins_raw_put_object(conn, df, nm)
    expect_equal(gdpins_raw_get(conn, nm)$x, 1:3, label = nm)
    expect_true(file.exists(gdpins_raw_path(conn, nm)), label = nm)
    gdpins_raw_remove(conn, nm)
    expect_false(file.exists(file.path(conn$local_path, nm)), label = nm)
  }
})

test_that(".raw_copy_to_local() refuses a Drive name that escapes local_path", {
  parent <- withr::local_tempdir()
  conn   <- new_sandboxed_raw_conn(parent, "drive_local")
  fake   <- file.path(parent, "fake_drive", "gdpins-fake")
  writeLines("B", file.path(fake, "sentinel.csv"))
  sentinel <- file.path(parent, "sentinel.csv")
  writeLines("A", sentinel)

  expect_error(
    .raw_copy_to_local(conn, "../sentinel.csv"),
    class = "gdpins_error_path_escape"
  )
  expect_identical(readLines(sentinel), "A")

  # Windows separators inside a Drive name.
  fs::dir_create(file.path(conn$local_path, "a"))
  writeLines("B", file.path(fake, "raw-exogenous", "x.csv"))
  writeLines("A", file.path(parent, "x.csv"))
  expect_error(
    .raw_copy_to_local(conn, "a\\..\\..\\x.csv"),
    class = "gdpins_error_path_escape"
  )
  expect_identical(readLines(file.path(parent, "x.csv")), "A")
})

test_that(".raw_copy_to_drive() refuses a name that escapes the Drive root", {
  parent <- withr::local_tempdir()
  conn   <- new_sandboxed_raw_conn(parent, "drive_local")
  writeLines("A", file.path(dirname(conn$local_path), "x.csv"))

  expect_error(
    .raw_copy_to_drive(conn, "../x.csv"),
    class = "gdpins_error_invalid_name"
  )
  expect_false(file.exists(file.path(parent, "fake_drive", "gdpins-fake", "x.csv")))
})

test_that("raw_connect sync_from_drive skips and warns on an unsafe Drive name", {
  parent  <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = file.path(parent, "fake_drive"))
  drive   <- file.path(parent, "fake_drive", "gdpins-fake", "raw-exogenous")
  fs::dir_create(drive)
  writeLines("ok", file.path(drive, "ok.csv"))
  # Real bytes behind the escaping name, so unfixed code really writes them.
  writeLines("evil", file.path(dirname(drive), "evil.csv"))
  local_path <- file.path(parent, "mirror")

  # The fake adapter's listing cannot yield a parent-escaping path, so inject
  # one the way a hostile Drive folder named ".." would surface.
  real_gd_ls <- gd_ls
  local_mocked_bindings(
    gd_ls = function(adapter, path, recursive = FALSE) {
      out <- real_gd_ls(adapter, path, recursive = recursive)
      extra <- out[1L, , drop = FALSE]
      extra$path <- paste0(path, "/../evil.csv")
      rbind(out, extra)
    },
    .package = "gdpins"
  )

  expect_warning(
    conn <- gdpins_raw_connect(
      drive_path     = "gdpins-fake/raw-exogenous",
      local_path     = local_path,
      adapter        = adapter,
      create         = FALSE,
      on_discrepancy = "sync_from_drive"
    ),
    class = "gdpins_warning_invalid_name"
  )
  expect_true(file.exists(file.path(local_path, "ok.csv")))
  expect_false(file.exists(file.path(parent, "evil.csv")))
})
