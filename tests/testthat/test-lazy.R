# Lazy board connection (?`lazy-boards`).
#
# The load-bearing claim is negative — init must NOT touch Drive — so most of
# these tests assert on a *counting adapter* that records every call reaching
# the Drive seam. `expect_no_error(init)` would pass even if init did all the
# work eagerly; a call count of zero is the only thing that proves laziness.

# ── Fixtures ─────────────────────────────────────────────────────────────────

#' Fake adapter that counts every Drive-seam call routed through it
#'
#' Wraps `gdpins_fake_drive()` and increments `$calls` (an environment, so the
#' count survives the adapter being copied into a board) on each closure hit.
#' @keywords internal
new_counting_adapter <- function(root = NULL) {
  if (is.null(root)) {
    root <- tempfile("gdpins_fake_drive_")
    fs::dir_create(root)
  }
  adapter <- gdpins_fake_drive(root = root)
  calls   <- new.env(parent = emptyenv())
  calls$n <- 0L

  for (nm in names(adapter)) {
    if (!is.function(adapter[[nm]])) next
    adapter[[nm]] <- local({
      fn <- adapter[[nm]]
      function(...) {
        calls$n <- calls$n + 1L
        fn(...)
      }
    })
  }
  adapter$calls <- calls
  adapter
}

#' A lazy drive_cache board over a counting adapter
#'
#' `on_discrepancy` defaults to `"ignore"`: an empty board has nothing to
#' reconcile, and the default ("warn" non-interactively) would fire a sync
#' warning at connect that is noise in every test here except the one that
#' asserts on it.
#' @keywords internal
new_lazy_board <- function(name = "lazytest", config = "drive_cache",
                           on_discrepancy = "ignore", ...) {
  adapter   <- new_counting_adapter()
  cache_dir <- tempfile("gdpins_cache_")
  local_dir <- if (config == "drive_cache_local") tempfile("gdpins_local_") else NULL
  board <- gdpins_init_board(
    name           = name,
    drive_path     = paste0("gdpins-fake/", name),
    cache_dir      = cache_dir,
    local_dir      = local_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = on_discrepancy,
    lazy           = TRUE,
    ...
  )
  list(board = board, adapter = adapter, cache_dir = cache_dir, local_dir = local_dir)
}

# ── 1. Init does no work ─────────────────────────────────────────────────────

test_that("lazy init touches neither Drive nor the filesystem", {
  fx <- new_lazy_board()

  expect_identical(fx$adapter$calls$n, 0L)
  expect_false(dir.exists(fx$cache_dir))
  expect_false(gdpins_board_is_connected(fx$board))
})

test_that("lazy init of a local_only board does not create local_dir", {
  local_dir <- tempfile("gdpins_local_")
  board <- gdpins_init_board(
    name      = "loc",
    local_dir = local_dir,
    lazy      = TRUE
  )

  expect_false(dir.exists(local_dir))
  expect_false(gdpins_board_is_connected(board))

  gdpins_board_connect(board, on_discrepancy = "ignore")
  expect_true(dir.exists(local_dir))
})

test_that("eager init does the work during the call", {
  adapter   <- new_counting_adapter()
  cache_dir <- tempfile("gdpins_cache_")
  board <- gdpins_init_board(
    name           = "eager",
    drive_path     = "gdpins-fake/eager",
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore",
    lazy           = FALSE
  )

  expect_gt(adapter$calls$n, 0L)
  expect_true(dir.exists(cache_dir))
  expect_true(gdpins_board_is_connected(board))
})

# ── 2. Declared fields never force ───────────────────────────────────────────

test_that("metadata fields are readable without connecting", {
  fx <- new_lazy_board(name = "meta")

  expect_identical(fx$board$name, "meta")
  expect_identical(fx$board$config, "drive_cache")
  expect_true(fx$board$versioned)
  expect_identical(fx$board$drive_path, "gdpins-fake/meta")
  expect_identical(fx$board$cache_dir, fx$cache_dir)
  expect_null(fx$board$local_dir)
  expect_s3_class(fx$board$adapter, "gdpins_drive_adapter")

  expect_identical(fx$adapter$calls$n, 0L)
  expect_false(gdpins_board_is_connected(fx$board))
})

test_that("print/format/summary describe a lazy board without connecting", {
  fx <- new_lazy_board(name = "quiet")

  fmt <- format(fx$board)
  expect_match(fmt, "DC-", fixed = TRUE)
  expect_match(fmt, "drive_cache")
  expect_lte(nchar(fmt), 80L)

  expect_no_error(print(fx$board))
  expect_no_error(summary(fx$board))

  expect_identical(fx$adapter$calls$n, 0L)
  expect_false(gdpins_board_is_connected(fx$board))
})

test_that("format component indicator is derived from config", {
  expect_match(format(new_fake_board(config = "local_only")), "--L", fixed = TRUE)
  expect_match(format(new_fake_board(config = "drive_cache")), "DC-", fixed = TRUE)
  expect_match(
    format(new_fake_board(config = "drive_cache_local")), "DCL",
    fixed = TRUE
  )
})

# ── 3. Component reads force ─────────────────────────────────────────────────

test_that("reading each component field connects the board", {
  for (field in c("drive_board", "cache_board")) {
    fx <- new_lazy_board(name = "force")
    expect_false(gdpins_board_is_connected(fx$board))

    expect_s3_class(fx$board[[field]], "pins_board")

    expect_true(gdpins_board_is_connected(fx$board), label = field)
    expect_gt(adapter_calls <- fx$adapter$calls$n, 0L)
  }
})

test_that("a lazy drive_cache board has no local_board after connecting", {
  fx <- new_lazy_board()
  expect_null(fx$board$local_board)
  expect_true(gdpins_board_is_connected(fx$board))
})

test_that("connecting happens once, not per access", {
  fx <- new_lazy_board()

  invisible(fx$board$drive_board)
  n_after_first <- fx$adapter$calls$n
  expect_gt(n_after_first, 0L)

  invisible(fx$board$drive_board)
  invisible(fx$board$cache_board)
  invisible(fx$board$local_board)

  expect_identical(fx$adapter$calls$n, n_after_first)
})

test_that("gdpins_pin_write connects a lazy board", {
  fx <- new_lazy_board()
  expect_false(gdpins_board_is_connected(fx$board))

  gdpins_pin_write(fx$board, fx_plain_tbl(), "tbl")

  expect_true(gdpins_board_is_connected(fx$board))
  expect_equal(gdpins_pin_read(fx$board, "tbl"), fx_plain_tbl())
})

test_that("gdpins_board_status connects a lazy board", {
  fx <- new_lazy_board()
  expect_false(gdpins_board_is_connected(fx$board))

  gdpins_board_status(fx$board)

  expect_true(gdpins_board_is_connected(fx$board))
})

# ── 4. Shared state ──────────────────────────────────────────────────────────

test_that("copies share one connection", {
  fx <- new_lazy_board()
  b2 <- fx$board

  invisible(b2$drive_board)

  expect_true(gdpins_board_is_connected(fx$board))
  expect_true(gdpins_board_is_connected(b2))
  expect_identical(fx$board$drive_board, b2$drive_board)
})

test_that("connecting inside a function is visible to the caller", {
  fx <- new_lazy_board()
  touch <- function(b) invisible(b$cache_board)

  touch(fx$board)

  expect_true(gdpins_board_is_connected(fx$board))
})

# ── 5. gdpins_board_connect ──────────────────────────────────────────────────

test_that("gdpins_board_connect forces and returns the board invisibly", {
  fx <- new_lazy_board()

  res <- withVisible(gdpins_board_connect(fx$board, on_discrepancy = "ignore"))

  expect_false(res$visible)
  expect_s3_class(res$value, "gdpins_board")
  expect_true(gdpins_board_is_connected(fx$board))
  expect_gt(fx$adapter$calls$n, 0L)
})

test_that("gdpins_board_connect is a no-op on a connected board", {
  fx <- new_lazy_board()
  gdpins_board_connect(fx$board, on_discrepancy = "ignore")
  n <- fx$adapter$calls$n

  gdpins_board_connect(fx$board, on_discrepancy = "ignore")

  expect_identical(fx$adapter$calls$n, n)
})

test_that("gdpins_board_connect is a no-op on an eager board", {
  board <- new_fake_board(config = "drive_cache")
  expect_true(gdpins_board_is_connected(board))
  expect_no_error(gdpins_board_connect(board))
})

test_that("the init on_discrepancy runs at connect time", {
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  fx <- new_lazy_board(name = "warner", on_discrepancy = "warn")
  expect_warning(gdpins_board_connect(fx$board), "sync discrepancy")
})

test_that("gdpins_board_connect on_discrepancy overrides the init value", {
  fx <- new_lazy_board(name = "override", on_discrepancy = "warn")
  expect_silent(gdpins_board_connect(fx$board, on_discrepancy = "ignore"))
})

test_that("gdpins_board_connect rejects an invalid on_discrepancy", {
  fx <- new_lazy_board()
  expect_error(gdpins_board_connect(fx$board, on_discrepancy = "nonsense"))
  # A rejected override must not half-connect the board.
  expect_false(gdpins_board_is_connected(fx$board))
})

test_that("gdpins_board_connect rejects non-boards", {
  expect_error(gdpins_board_connect("nope"), "must be a")
  expect_error(gdpins_board_is_connected(42), "must be a")
})

# ── 6. Deferred failures ─────────────────────────────────────────────────────

test_that("a bad drive_path errors at first use, not at init", {
  adapter <- new_counting_adapter()

  board <- expect_no_error(
    gdpins_init_board(
      name       = "missing",
      drive_path = "gdpins-fake/does-not-exist",
      cache_dir  = tempfile("gdpins_cache_"),
      adapter    = adapter,
      create     = FALSE,
      lazy       = TRUE
    )
  )

  expect_error(board$drive_board, "refusing to create")
})

test_that("a failed connection leaves the board retryable", {
  adapter <- new_counting_adapter()
  board <- gdpins_init_board(
    name           = "retry",
    drive_path     = "gdpins-fake/retry",
    cache_dir      = tempfile("gdpins_cache_"),
    adapter        = adapter,
    create         = FALSE,
    on_discrepancy = "ignore",
    lazy           = TRUE
  )

  expect_error(board$drive_board)
  expect_false(gdpins_board_is_connected(board))

  # Create the folder behind the board's back; the retry must now succeed
  # rather than replay the cached failure.
  gd_mkdir(adapter, "gdpins-fake/retry")

  expect_s3_class(board$drive_board, "pins_board")
  expect_true(gdpins_board_is_connected(board))
})

# ── 7. lazy resolution ───────────────────────────────────────────────────────

test_that("lazy defaults to TRUE", {
  adapter <- new_counting_adapter()
  board <- gdpins_init_board(
    name       = "default",
    drive_path = "gdpins-fake/default",
    cache_dir  = tempfile("gdpins_cache_"),
    adapter    = adapter,
    create     = TRUE
  )
  expect_false(gdpins_board_is_connected(board))
  expect_identical(adapter$calls$n, 0L)
})

test_that("gdpins.lazy_boards = FALSE makes init eager", {
  withr::local_options(gdpins.lazy_boards = FALSE)
  adapter <- new_counting_adapter()

  board <- gdpins_init_board(
    name           = "opt",
    drive_path     = "gdpins-fake/opt",
    cache_dir      = tempfile("gdpins_cache_"),
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  expect_true(gdpins_board_is_connected(board))
  expect_gt(adapter$calls$n, 0L)
})

test_that("an explicit lazy argument beats the option", {
  withr::local_options(gdpins.lazy_boards = FALSE)
  adapter <- new_counting_adapter()

  board <- gdpins_init_board(
    name       = "explicit",
    drive_path = "gdpins-fake/explicit",
    cache_dir  = tempfile("gdpins_cache_"),
    adapter    = adapter,
    create     = TRUE,
    lazy       = TRUE
  )

  expect_false(gdpins_board_is_connected(board))
  expect_identical(adapter$calls$n, 0L)
})

test_that("lazy must be a non-NA logical scalar", {
  expect_error(
    gdpins_init_board(name = "x", local_dir = tempfile(), lazy = NA),
    "non-NA logical scalar"
  )
  expect_error(
    gdpins_init_board(name = "x", local_dir = tempfile(), lazy = "yes"),
    "non-NA logical scalar"
  )
})

test_that("argument validation still fires eagerly", {
  # Cheap checks must not be deferred — a lazy board with bad arguments would
  # be a worse error than no board at all.
  expect_error(gdpins_init_board(name = ""), "non-empty character")
  expect_error(gdpins_init_board(name = "x"), "At least one of")
  expect_error(
    gdpins_init_board(name = "x", drive_path = "p", cache_dir = "c"),
    "adapter.*required"
  )
  expect_error(
    gdpins_init_board(name = "x", drive_path = "p", adapter = gdpins_fake_drive()),
    "cache_dir.*required"
  )
  expect_error(
    gdpins_init_board(name = "x", local_dir = tempfile(), versioned = NA),
    "non-NA logical scalar"
  )
})

# ── 8. Extraction semantics ──────────────────────────────────────────────────

test_that("[[ and $ agree on lazy and eager boards", {
  fx <- new_lazy_board()
  expect_identical(fx$board[["name"]], fx$board$name)
  expect_identical(fx$board[["drive_board"]], fx$board$drive_board)

  eager <- new_fake_board(config = "drive_cache")
  expect_identical(eager[["name"]], eager$name)
  expect_identical(eager[["drive_board"]], eager$drive_board)
})

test_that("unknown fields are NULL, not an error", {
  fx <- new_lazy_board()
  expect_null(fx$board$nonesuch)
  expect_null(fx$board[["nonesuch"]])
  expect_false(gdpins_board_is_connected(fx$board))

  gdpins_board_connect(fx$board, on_discrepancy = "ignore")
  expect_null(fx$board$nonesuch)
})

test_that("[[ rejects non-scalar-character indices", {
  fx <- new_lazy_board()
  expect_error(fx$board[[1L]], "single field name")
  expect_error(fx$board[[c("a", "b")]], "single field name")
})

test_that("field access does not partial-match", {
  # `$` on a bare list partial-matches; the gdpins_board method does not.
  # "drive" is ambiguous between drive_board and drive_path anyway.
  fx <- new_lazy_board()
  expect_null(fx$board$vers)
  expect_true(fx$board$versioned)
})
