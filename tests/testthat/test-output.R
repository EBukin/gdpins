# test-output.R — WS8: gdpins_save_figure + gdpins_publish_output

# ── gdpins_save_figure ────────────────────────────────────────────────────────

test_that("save_figure renders PNG to a file", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  p   <- fx_ggplot()
  out <- gdpins_save_figure(p, "my_fig", dir, dpi = 72)
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0L)
  expect_equal(basename(out), "my_fig.png")
})

test_that("save_figure renders SVG to a file", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("svglite")
  dir <- withr::local_tempdir()
  p   <- fx_ggplot()
  out <- gdpins_save_figure(p, "my_fig", dir, device = "svg", dpi = 72)
  expect_true(file.exists(out))
  expect_gt(file.size(out), 0L)
  expect_equal(basename(out), "my_fig.svg")
})

test_that("save_figure default device is png", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  out <- gdpins_save_figure(fx_ggplot(), "fig", dir, dpi = 72)
  expect_true(endsWith(out, ".png"))
})

test_that("save_figure returns path invisibly", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  res <- withVisible(gdpins_save_figure(fx_ggplot(), "fig", dir, dpi = 72))
  expect_false(res$visible)
  expect_equal(basename(res$value), "fig.png")
})

test_that("save_figure creates dir if it does not exist", {
  skip_if_not_installed("ggplot2")
  parent  <- withr::local_tempdir()
  new_dir <- file.path(parent, "subdir", "figures")
  expect_false(dir.exists(new_dir))
  out <- gdpins_save_figure(fx_ggplot(), "fig", new_dir, dpi = 72)
  expect_true(dir.exists(new_dir))
  expect_true(file.exists(out))
})

test_that("ggplot object is NOT persisted — only the image file", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  gdpins_save_figure(fx_ggplot(), "myfig", dir, dpi = 72)
  files <- list.files(dir, full.names = FALSE)
  # Only the rendered image file should exist — no .rds or binary object files
  expect_equal(files, "myfig.png")
  expect_length(list.files(dir, pattern = "\\.rds$"), 0L)
})

test_that("save_figure: unknown device triggers match.arg error", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  expect_error(
    gdpins_save_figure(fx_ggplot(), "fig", dir, device = "pdf"),
    regexp = "arg"
  )
})

test_that("save_figure: invalid name scalar triggers error", {
  skip_if_not_installed("ggplot2")
  dir <- withr::local_tempdir()
  expect_error(
    gdpins_save_figure(fx_ggplot(), c("a", "b"), dir, dpi = 72),
    class = "rlang_error"
  )
  expect_error(
    gdpins_save_figure(fx_ggplot(), "", dir, dpi = 72),
    class = "rlang_error"
  )
})

test_that("save_figure: invalid dir scalar triggers error", {
  skip_if_not_installed("ggplot2")
  expect_error(
    gdpins_save_figure(fx_ggplot(), "fig", c("a", "b"), dpi = 72),
    class = "rlang_error"
  )
})

# ── gdpins_publish_output ─────────────────────────────────────────────────────

# gdpins_is_online() is a WS2 stub in this test tier.
# We mock it throughout all publish tests using local_mocked_bindings.
# The pattern: call local_mocked_bindings(name = fn, .package = "gdpins")
# at the top of the test; it auto-resets at test teardown.

test_that("publish: Drive is empty before publish is called (local-first)", {
  board   <- new_fake_board("drive_cache")
  adapter <- board$adapter

  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "almaty_summary", type = "rds")

  # Drive destination should NOT exist before publish
  expect_false(gd_exists(adapter, "output-tables"))
  expect_false(gd_exists(adapter, "output-tables/almaty_summary.rds"))
})

test_that("publish: tables mirror to fake Drive after publish", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board   <- new_fake_board("drive_cache")
  adapter <- board$adapter

  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "almaty_summary", type = "rds")

  gdpins_publish_output(
    tables_board = board,
    drive_tables = "output-tables",
    adapter      = adapter
  )

  expect_true(gd_exists(adapter, "output-tables/almaty_summary.rds"))
})

test_that("publish: figures upload to fake Drive after publish", {
  skip_if_not_installed("ggplot2")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  figs_dir <- withr::local_tempdir()
  gdpins_save_figure(fx_ggplot(), "fig_a", figs_dir, dpi = 72)
  gdpins_save_figure(fx_ggplot(), "fig_b", figs_dir, dpi = 72)

  adapter <- gdpins_fake_drive()

  gdpins_publish_output(
    figures_dir   = figs_dir,
    drive_figures = "output-figures",
    adapter       = adapter
  )

  expect_true(gd_exists(adapter, "output-figures/fig_a.png"))
  expect_true(gd_exists(adapter, "output-figures/fig_b.png"))
})

test_that("publish: dry_run changes nothing on Drive", {
  skip_if_not_installed("ggplot2")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board    <- new_fake_board("drive_cache")
  adapter  <- board$adapter
  figs_dir <- withr::local_tempdir()

  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "summary", type = "rds")
  gdpins_save_figure(fx_ggplot(), "fig_a", figs_dir, dpi = 72)

  expect_message(
    gdpins_publish_output(
      tables_board  = board,
      figures_dir   = figs_dir,
      adapter       = adapter,
      dry_run       = TRUE
    ),
    regexp = "Dry-run"
  )

  expect_false(gd_exists(adapter, "output-tables/summary.rds"))
  expect_false(gd_exists(adapter, "output-figures/fig_a.png"))
})

test_that("publish: dry_run reports table and figure counts", {
  skip_if_not_installed("ggplot2")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board    <- new_fake_board("drive_cache")
  adapter  <- board$adapter
  figs_dir <- withr::local_tempdir()

  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "kaz_summary", type = "rds")
  gdpins_save_figure(fx_ggplot(), "fig_kaz", figs_dir, dpi = 72)

  msgs <- character()
  withCallingHandlers(
    gdpins_publish_output(
      tables_board  = board,
      figures_dir   = figs_dir,
      adapter       = adapter,
      dry_run       = TRUE
    ),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  combined <- paste(msgs, collapse = " ")
  expect_true(grepl("Dry-run", combined, ignore.case = TRUE))
})

test_that("publish: offline is blocked with cli_abort", {
  local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  adapter <- gdpins_fake_drive()
  expect_error(
    gdpins_publish_output(adapter = adapter),
    class = "rlang_error"
  )
})

test_that("publish: no adapter → cli_abort", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  expect_error(
    gdpins_publish_output(tables_board = NULL, figures_dir = NULL),
    class = "rlang_error"
  )
})

test_that("publish: adapter taken from tables_board when not supplied", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board     <- new_fake_board("drive_cache")
  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "tbl_a", type = "rds")

  gdpins_publish_output(tables_board = board)

  expect_true(gd_exists(board$adapter, "output-tables/tbl_a.rds"))
})

test_that("publish: local-first — local_board used over cache_board", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board <- new_fake_board("drive_cache_local")
  # Write ONLY to local_board (not cache_board)
  pins::pin_write(board$local_board, fx_output_table(), "local_only_pin", type = "rds")

  gdpins_publish_output(tables_board = board)

  expect_true(gd_exists(board$adapter, "output-tables/local_only_pin.rds"))
})

test_that("publish: nothing to publish emits a message", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  adapter <- gdpins_fake_drive()
  expect_message(
    gdpins_publish_output(adapter = adapter),
    regexp = "Nothing"
  )
})

test_that("publish: figures_dir NULL publishes nothing to figures drive folder", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  board     <- new_fake_board("drive_cache")
  adapter   <- board$adapter
  src_board <- board$cache_board
  pins::pin_write(src_board, fx_output_table(), "tbl_x", type = "rds")

  gdpins_publish_output(
    tables_board  = board,
    figures_dir   = NULL,
    adapter       = adapter
  )

  expect_false(gd_exists(adapter, "output-figures"))
  expect_true(gd_exists(adapter, "output-tables/tbl_x.rds"))
})

test_that("publish: tables_board NULL publishes nothing to tables drive folder", {
  skip_if_not_installed("ggplot2")
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  figs_dir <- withr::local_tempdir()
  gdpins_save_figure(fx_ggplot(), "fig_x", figs_dir, dpi = 72)

  adapter <- gdpins_fake_drive()

  gdpins_publish_output(
    tables_board  = NULL,
    figures_dir   = figs_dir,
    adapter       = adapter
  )

  expect_false(gd_exists(adapter, "output-tables"))
  expect_true(gd_exists(adapter, "output-figures/fig_x.png"))
})

test_that("publish: returns invisibly NULL", {
  local_mocked_bindings(gdpins_is_online = function() TRUE, .package = "gdpins")
  adapter <- gdpins_fake_drive()
  res <- withVisible(gdpins_publish_output(adapter = adapter))
  expect_false(res$visible)
  expect_null(res$value)
})

# ── .resolve_read_board ───────────────────────────────────────────────────────

test_that(".resolve_read_board: local_board takes priority", {
  board  <- new_fake_board("drive_cache_local")
  result <- gdpins:::.resolve_read_board(board)
  expect_identical(result, board$local_board)
})

test_that(".resolve_read_board: cache_board when no local_board", {
  board  <- new_fake_board("drive_cache")
  result <- gdpins:::.resolve_read_board(board)
  expect_identical(result, board$cache_board)
})

test_that(".resolve_read_board: drive_board as last resort", {
  fake_root   <- withr::local_tempdir()
  adapter     <- gdpins_fake_drive(root = fake_root)
  drive_dir   <- file.path(fake_root, "only_drive")
  fs::dir_create(drive_dir)
  drive_board <- pins::board_folder(drive_dir)
  board <- new_gdpins_board(
    config      = "drive_cache",
    name        = "test_drive_only",
    drive_board = drive_board,
    cache_board = NULL,
    adapter     = adapter,
    versioned   = TRUE
  )
  result <- gdpins:::.resolve_read_board(board)
  expect_identical(result, board$drive_board)
})

# ── .collect_tables_work ──────────────────────────────────────────────────────

test_that(".collect_tables_work: NULL board returns empty tibble", {
  result <- gdpins:::.collect_tables_work(NULL)
  expect_s3_class(result, "tbl_df")
  expect_equal(names(result), "pin_name")
  expect_equal(nrow(result), 0L)
})

test_that(".collect_tables_work: seeded board returns pin names", {
  board <- new_fake_board("local_only")
  pins::pin_write(board$local_board, fx_output_table(), "tbl_one", type = "rds")
  pins::pin_write(board$local_board, fx_output_table(), "tbl_two", type = "rds")
  result <- gdpins:::.collect_tables_work(board)
  expect_setequal(result$pin_name, c("tbl_one", "tbl_two"))
})

# ── .collect_figures_work ─────────────────────────────────────────────────────

test_that(".collect_figures_work: NULL returns empty tibble", {
  result <- gdpins:::.collect_figures_work(NULL)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that(".collect_figures_work: nonexistent dir returns empty tibble", {
  result <- gdpins:::.collect_figures_work(tempfile("nonexistent_"))
  expect_equal(nrow(result), 0L)
})

test_that(".collect_figures_work: lists only png/svg files", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("svglite")
  dir <- withr::local_tempdir()
  gdpins_save_figure(fx_ggplot(), "a", dir, device = "png", dpi = 72)
  gdpins_save_figure(fx_ggplot(), "b", dir, device = "svg", dpi = 72)
  writeLines("x", file.path(dir, "readme.txt"))
  result <- gdpins:::.collect_figures_work(dir)
  expect_setequal(result$file_name, c("a.png", "b.svg"))
})
