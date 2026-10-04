# Real Drive adapter (gdpins_real_drive) with every googledrive call mocked.
# Nothing here reaches the network: drive_get / drive_ls / drive_mkdir /
# drive_upload / drive_update / drive_download / drive_trash are replaced in
# the googledrive namespace. The drive_ls mock applies `pattern` exactly as
# upstream does (client-side grep on the fetched names), so a regex-matching
# bug in the adapter shows up here.

root_id <- "rootid0123456789abcdefghijk"

# `tree`: named list, parent Drive id -> fake_dribble() of its children.
# Returns an environment whose `calls` records every mutating googledrive call
# and whose `adapter` is a real adapter over the mocked tree.
local_real_drive <- function(tree = list(), ls_error = NULL,
                             env = parent.frame()) {
  rec <- new.env(parent = emptyenv())
  rec$calls <- character()
  rec$tree  <- tree
  tree_get <- function(id) {
    kids <- rec$tree[[id]]
    if (is.null(kids)) fake_dribble() else kids
  }

  local_mocked_bindings(
    gdpins_ensure_drive_auth = function(email) invisible(NULL),
    .package = "gdpins",
    .env = env
  )
  local_mocked_bindings(
    drive_get = function(...) fake_folder_dribble("root", id = root_id),
    drive_ls = function(path = NULL, ..., recursive = FALSE) {
      if (!is.null(ls_error)) ls_error()
      res <- tree_get(path$id[[1L]])
      pattern <- list(...)$pattern
      if (!is.null(pattern)) {
        res <- res[grep(pattern, res$name), , drop = FALSE]
      }
      res
    },
    drive_mkdir = function(name, path = NULL, ...) {
      rec$calls <- c(rec$calls, paste0("drive_mkdir:", name))
      d <- fake_folder_dribble(name, id = paste0("new_", name))
      parent <- path$id[[1L]]
      rec$tree[[parent]] <- rbind(tree_get(parent), d)
      d
    },
    drive_upload = function(media, path = NULL, name = NULL, ...) {
      rec$calls <- c(rec$calls, paste0("drive_upload:", name))
      invisible(fake_dribble(name))
    },
    drive_update = function(file, media = NULL, ...) {
      rec$calls <- c(rec$calls, paste0("drive_update:", file$id[[1L]]))
      invisible(file)
    },
    drive_download = function(file, path = NULL, overwrite = FALSE, ...) {
      rec$calls <- c(rec$calls, paste0("drive_download:", file$id[[1L]]))
      invisible(file)
    },
    drive_trash = function(file, ...) {
      rec$calls <- c(rec$calls, paste0("drive_trash:", file$id[[1L]]))
      invisible(file)
    },
    .package = "googledrive",
    .env = env
  )

  rec$adapter <- gdpins_real_drive(root_id, email = "")
  rec
}

drive_403 <- function() {
  cli::cli_abort("403 Forbidden", class = "httr2_http_403")
}

# ── H3: names are matched literally, not as regular expressions ──────────────

test_that("exists() finds a name containing regex metacharacters", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble("quarterly report (Q1 2024).csv")
  ))
  expect_true(rec$adapter$exists("quarterly report (Q1 2024).csv"))
})

test_that("get_id() does not over-match: '.' is not a wildcard", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble(
      c("abcsv", "axcsv", "a.csv"),
      id = c("id_b", "id_x", "id_a")
    )
  ))
  expect_identical(rec$adapter$get_id("a.csv"), "id_a")
})

test_that("nested paths resolve segment by segment with exact names", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_folder_dribble(
      c("dataXraw", "data.raw"), id = c("id_wrong", "id_dir")
    ),
    id_dir = fake_dribble("f+1.csv", id = "id_f")
  ))
  expect_identical(rec$adapter$get_id("data.raw/f+1.csv"), "id_f")
  expect_identical(gd_md5(rec$adapter, "data.raw/f+1.csv"),
                   "d41d8cd98f00b204e9800998ecf8427e")
})

test_that("duplicate Drive names error instead of picking one", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble(
      c("a.csv", "a.csv"),
      id    = c("id_1", "id_2"),
      mtime = c("2024-01-01T00:00:00.000Z", "2024-02-01T00:00:00.000Z")
    )
  ))
  expect_error(
    rec$adapter$exists("a.csv"),
    class = "gdpins_error_ambiguous_drive_name"
  )
  expect_snapshot(rec$adapter$exists("a.csv"), error = TRUE)
})

test_that("duplicate names in upload() error before writing", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble(
      c("a.csv", "a.csv"), id = c("id_1", "id_2")
    )
  ))
  tmp <- withr::local_tempfile(lines = "x")
  expect_error(
    gd_upload(rec$adapter, tmp, "a.csv"),
    class = "gdpins_error_ambiguous_drive_name"
  )
  expect_length(rec$calls, 0L)
})

test_that("upload() updates an existing file whose name has metacharacters", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble(
      "report (final).csv", id = "id_rep"
    )
  ))
  tmp <- withr::local_tempfile(lines = "x")
  gd_upload(rec$adapter, tmp, "report (final).csv")
  expect_identical(rec$calls, "drive_update:id_rep")
})

test_that("mkdir() reuses an existing folder whose name has metacharacters", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_folder_dribble("data (raw)")
  ))
  gd_mkdir(rec$adapter, "data (raw)")
  expect_identical(rec$calls, character())
})

test_that("trash() trashes the exact match only", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble(
      c("abcsv", "a.csv"), id = c("id_b", "id_a")
    )
  ))
  gd_trash(rec$adapter, "a.csv")
  expect_identical(rec$calls, "drive_trash:id_a")
})

test_that("ls() maps a listing to the adapter tibble", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = rbind(
      fake_folder_dribble("sub (1)", id = "id_sub"),
      fake_dribble("top.csv", id = "id_top")
    ),
    id_sub = fake_dribble("in.csv", id = "id_in")
  ))
  flat <- gd_ls(rec$adapter, "")
  expect_setequal(flat$path, c("sub (1)", "top.csv"))
  deep <- gd_ls(rec$adapter, "", recursive = TRUE)
  expect_setequal(deep$path, c("sub (1)", "top.csv", "sub (1)/in.csv"))
  expect_identical(unname(deep$drive_id[deep$path == "sub (1)/in.csv"]), "id_in")
  sub <- gd_ls(rec$adapter, "sub (1)")
  expect_identical(sub$path, "sub (1)/in.csv")
  expect_equal(nrow(gd_ls(rec$adapter, "missing")), 0L)
})

test_that("absent paths still read as absent", {
  rec <- local_real_drive(list(
    rootid0123456789abcdefghijk = fake_dribble("other.csv")
  ))
  expect_false(gd_exists(rec$adapter, "x.csv"))
  expect_identical(rec$adapter$get_id("x.csv"), NA_character_)
  expect_true(is.na(gd_mtime(rec$adapter, "x.csv")))
  tmp <- withr::local_tempfile(lines = "x")
  gd_upload(rec$adapter, tmp, "x.csv")
  expect_identical(rec$calls, "drive_upload:x.csv")
})

# ── H4: Drive errors propagate instead of reading as "absent" ────────────────

test_that("exists() propagates a drive_ls error", {
  rec <- local_real_drive(ls_error = drive_403)
  expect_error(gd_exists(rec$adapter, "x"), class = "httr2_http_403")
})

test_that("ls() propagates a drive_ls error, flat and recursive", {
  rec <- local_real_drive(ls_error = drive_403)
  expect_error(gd_ls(rec$adapter, ""), class = "httr2_http_403")
  expect_error(gd_ls(rec$adapter, "", recursive = TRUE),
               class = "httr2_http_403")
})

test_that("mkdir() propagates a drive_ls error and creates nothing", {
  rec <- local_real_drive(ls_error = drive_403)
  expect_error(gd_mkdir(rec$adapter, "sub"), class = "httr2_http_403")
  expect_identical(rec$calls, character())
})

test_that("upload() propagates a drive_ls error and writes nothing", {
  rec <- local_real_drive(ls_error = drive_403)
  tmp <- withr::local_tempfile(lines = "x")
  expect_error(gd_upload(rec$adapter, tmp, "x.csv"), class = "httr2_http_403")
  expect_identical(rec$calls, character())
})
