# test-drive-adapter.R — fake drive adapter round-trip tests

test_that("gdpins_fake_drive() returns a gdpins_drive_adapter", {
  adapter <- gdpins_fake_drive()
  expect_s3_class(adapter, "gdpins_drive_adapter")
  expect_equal(adapter$kind, "fake")
  expect_true(is.character(adapter$root))
  expect_true(fs::dir_exists(adapter$root))
})

test_that("gd_exists() returns FALSE for missing paths", {
  adapter <- gdpins_fake_drive()
  expect_false(gd_exists(adapter, "does_not_exist.txt"))
  expect_false(gd_exists(adapter, "subdir/missing.parquet"))
})

test_that("gd_mkdir() creates directory and is idempotent", {
  adapter <- gdpins_fake_drive()
  gd_mkdir(adapter, "test_dir")
  expect_true(gd_exists(adapter, "test_dir"))

  # Idempotent — calling again does not error
  expect_no_error(gd_mkdir(adapter, "test_dir"))
  expect_true(gd_exists(adapter, "test_dir"))
})

test_that("gd_mkdir() creates nested directories", {
  adapter <- gdpins_fake_drive()
  gd_mkdir(adapter, "parent/child/grandchild")
  expect_true(gd_exists(adapter, "parent/child/grandchild"))
})

test_that("gd_mkdir() returns invisible(adapter)", {
  adapter <- gdpins_fake_drive()
  result <- gd_mkdir(adapter, "mydir")
  expect_identical(result, adapter)
})

test_that("gd_upload() uploads a local file to the fake drive", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("hello gdpins", local_tmp)

  gd_upload(adapter, local_tmp, "uploaded.txt")
  expect_true(gd_exists(adapter, "uploaded.txt"))
})

test_that("gd_upload() creates parent directory automatically", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".csv")
  writeLines("a,b\n1,2", local_tmp)

  gd_upload(adapter, local_tmp, "subdir/data.csv")
  expect_true(gd_exists(adapter, "subdir/data.csv"))
})

test_that("gd_upload() overwrites an existing file", {
  adapter   <- gdpins_fake_drive()
  local_v1  <- tempfile(fileext = ".txt")
  local_v2  <- tempfile(fileext = ".txt")
  writeLines("version 1", local_v1)
  writeLines("version 2", local_v2)

  gd_upload(adapter, local_v1, "file.txt")
  md5_v1 <- gd_md5(adapter, "file.txt")

  gd_upload(adapter, local_v2, "file.txt")
  md5_v2 <- gd_md5(adapter, "file.txt")

  expect_false(identical(md5_v1, md5_v2))
})

test_that("gd_upload() returns invisible(adapter)", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("test", local_tmp)
  result <- gd_upload(adapter, local_tmp, "f.txt")
  expect_identical(result, adapter)
})

test_that("gd_download() downloads a file to a local path", {
  adapter   <- gdpins_fake_drive()
  local_src <- tempfile(fileext = ".txt")
  local_dst <- tempfile(fileext = ".txt")
  writeLines("round-trip content", local_src)

  gd_upload(adapter, local_src, "round_trip.txt")
  gd_download(adapter, "round_trip.txt", local_dst)

  expect_true(file.exists(local_dst))
  expect_equal(readLines(local_dst), "round-trip content")
})

test_that("gd_download() returns invisible(local_path)", {
  adapter   <- gdpins_fake_drive()
  local_src <- tempfile(fileext = ".txt")
  local_dst <- tempfile(fileext = ".txt")
  writeLines("data", local_src)
  gd_upload(adapter, local_src, "f.txt")

  result <- gd_download(adapter, "f.txt", local_dst)
  expect_equal(result, local_dst)
})

test_that("gd_download() errors for missing path", {
  adapter   <- gdpins_fake_drive()
  local_dst <- tempfile(fileext = ".txt")
  expect_error(gd_download(adapter, "missing.txt", local_dst))
})

test_that("gd_md5() returns character md5 for an uploaded file", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("md5 content", local_tmp)
  gd_upload(adapter, local_tmp, "hashme.txt")

  md5 <- gd_md5(adapter, "hashme.txt")
  expect_type(md5, "character")
  expect_equal(nchar(md5), 32L)
})

test_that("gd_md5() matches tools::md5sum on the source file", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".bin")
  writeBin(as.raw(0:255), local_tmp)
  gd_upload(adapter, local_tmp, "binary.bin")

  expect_equal(
    gd_md5(adapter, "binary.bin"),
    unname(tools::md5sum(local_tmp))
  )
})

test_that("gd_md5() returns NA_character_ for missing path", {
  adapter <- gdpins_fake_drive()
  expect_identical(gd_md5(adapter, "nope.txt"), NA_character_)
})

test_that("gd_md5() returns NA_character_ for a directory", {
  adapter <- gdpins_fake_drive()
  gd_mkdir(adapter, "mydir")
  expect_identical(gd_md5(adapter, "mydir"), NA_character_)
})

test_that("gd_mtime() returns POSIXct for an existing file", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("time test", local_tmp)
  gd_upload(adapter, local_tmp, "timed.txt")

  mt <- gd_mtime(adapter, "timed.txt")
  expect_s3_class(mt, "POSIXct")
  expect_false(is.na(mt))
})

test_that("gd_mtime() returns NA POSIXct for missing path", {
  adapter <- gdpins_fake_drive()
  mt <- gd_mtime(adapter, "does_not_exist.txt")
  expect_s3_class(mt, "POSIXct")
  expect_true(is.na(mt))
})

test_that("gd_ls() returns a tibble with correct columns", {
  adapter <- gdpins_fake_drive()
  result  <- gd_ls(adapter)

  expect_s3_class(result, "data.frame")
  expect_named(result, c("path", "is_dir", "size", "md5", "mtime", "drive_id"))
  expect_type(result$path,   "character")
  expect_type(result$is_dir, "logical")
  expect_type(result$size,   "double")
  expect_type(result$md5,    "character")
  expect_s3_class(result$mtime, "POSIXct")
  expect_type(result$drive_id, "character")
})

test_that("gd_ls() lists uploaded files and directories", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".csv")
  writeLines("x,y\n1,2", local_tmp)
  gd_mkdir(adapter, "subdir")
  gd_upload(adapter, local_tmp, "data.csv")

  result <- gd_ls(adapter)
  paths  <- result$path

  expect_true(any(grepl("data.csv", paths, fixed = TRUE)))
  expect_true(any(grepl("subdir",   paths, fixed = TRUE)))
})

test_that("gd_trash() makes a file invisible to gd_exists()", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("to trash", local_tmp)
  gd_upload(adapter, local_tmp, "trash_me.txt")
  expect_true(gd_exists(adapter, "trash_me.txt"))

  gd_trash(adapter, "trash_me.txt")
  expect_false(gd_exists(adapter, "trash_me.txt"))
})

test_that("gd_trash() excludes the file from gd_ls()", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("to trash", local_tmp)
  gd_upload(adapter, local_tmp, "trash_ls.txt")

  gd_trash(adapter, "trash_ls.txt")
  result <- gd_ls(adapter)
  expect_false(any(grepl("trash_ls.txt", result$path, fixed = TRUE)))
})

test_that("gd_trash() is recoverable (file not hard-deleted)", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("recoverable", local_tmp)
  gd_upload(adapter, local_tmp, "recoverable.txt")

  gd_trash(adapter, "recoverable.txt")

  # The entry should be in the state$trash store
  expect_true("recoverable.txt" %in% names(adapter$state$trash))
  # The trash key points to a file path that exists on disk
  trash_path <- adapter$state$trash[["recoverable.txt"]]
  expect_true(file.exists(trash_path))
})

test_that("gd_trash() returns invisible(adapter)", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("x", local_tmp)
  gd_upload(adapter, local_tmp, "x.txt")
  result <- gd_trash(adapter, "x.txt")
  expect_identical(result, adapter)
})

test_that("gd_trash() on missing path is a no-op", {
  adapter <- gdpins_fake_drive()
  expect_no_error(gd_trash(adapter, "nope.txt"))
})

test_that("upload→exists→md5→mtime→download identity round-trip", {
  adapter    <- gdpins_fake_drive()
  local_src  <- tempfile(fileext = ".rds")
  local_dst  <- tempfile(fileext = ".rds")
  saveRDS(list(a = 1, b = "test"), local_src)

  gd_upload(adapter, local_src, "round_trip.rds")
  expect_true(gd_exists(adapter, "round_trip.rds"))
  expect_equal(gd_md5(adapter, "round_trip.rds"), unname(tools::md5sum(local_src)))
  expect_false(is.na(gd_mtime(adapter, "round_trip.rds")))

  gd_download(adapter, "round_trip.rds", local_dst)
  src_obj <- readRDS(local_src)
  dst_obj <- readRDS(local_dst)
  expect_identical(src_obj, dst_obj)
})

test_that("gd_ls() with recursive = TRUE lists nested files", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("nested", local_tmp)

  gd_mkdir(adapter, "a/b")
  gd_upload(adapter, local_tmp, "a/b/deep.txt")

  result_shallow  <- gd_ls(adapter, recursive = FALSE)
  result_deep     <- gd_ls(adapter, recursive = TRUE)

  expect_true(nrow(result_deep) >= nrow(result_shallow))
  expect_true(any(grepl("deep.txt", result_deep$path, fixed = TRUE)))
})

test_that("gd_ls() returns empty tibble for a non-existent path", {
  adapter <- gdpins_fake_drive()
  result  <- gd_ls(adapter, "no_such_dir")
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
  expect_named(result, c("path", "is_dir", "size", "md5", "mtime", "drive_id"))
})

test_that("gd_ls() returns empty tibble when all entries are trashed", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("will be trashed", local_tmp)
  gd_upload(adapter, local_tmp, "to_trash.txt")

  gd_trash(adapter, "to_trash.txt")
  result <- gd_ls(adapter)
  expect_equal(nrow(result), 0L)
})

test_that("gd_download() errors when path is in trash", {
  adapter   <- gdpins_fake_drive()
  local_src <- tempfile(fileext = ".txt")
  local_dst <- tempfile(fileext = ".txt")
  writeLines("trash guard test", local_src)
  gd_upload(adapter, local_src, "trashed_file.txt")
  gd_trash(adapter, "trashed_file.txt")

  expect_error(gd_download(adapter, "trashed_file.txt", local_dst))
})

test_that("gd_ls() relative paths use forward-slash separator", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".txt")
  writeLines("rel path test", local_tmp)
  gd_mkdir(adapter, "subdir/nested")
  gd_upload(adapter, local_tmp, "subdir/nested/file.txt")

  result <- gd_ls(adapter, recursive = TRUE)
  # All relative paths must use "/" not "\"
  expect_true(all(!grepl("\\\\", result$path)))
  expect_true(any(grepl("subdir", result$path, fixed = TRUE)))
})

test_that(".is_drive_id detects IDs vs paths", {
  # Real Drive IDs: alphanumeric only, >= 25 chars
  expect_true(.is_drive_id("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"))
  expect_true(.is_drive_id("0B5q9muIMiDRoOWlFTjgzXzZLSkE"))  # old-style 28-char
  # Path strings
  expect_false(.is_drive_id("folder/subfolder"))
  expect_false(.is_drive_id("My Drive"))
  expect_false(.is_drive_id("disc-20260628T151324"))   # timestamped, has hyphen
  expect_false(.is_drive_id("geo3857"))                # short name
  # Edge cases
  expect_false(.is_drive_id(""))
  expect_false(.is_drive_id(NA_character_))
  expect_false(.is_drive_id("shortalphanumeric"))      # too short (< 25 chars)
})

test_that("gdpins_drive_url returns NA for fake adapter with message", {
  adapter <- gdpins_fake_drive()
  expect_message(
    url <- gdpins_drive_url(adapter),
    "Fake Drive"
  )
  expect_true(is.na(url))
})

test_that("gdpins_drive_url returns NA for fake adapter with path", {
  adapter <- gdpins_fake_drive()
  expect_message(
    url <- gdpins_drive_url(adapter, "some/path"),
    "Fake Drive"
  )
  expect_true(is.na(url))
})

test_that("gdpins_real_drive is exported and creates adapter", {
  local_mocked_bindings(
    gdpins_ensure_drive_auth = function(email) invisible(NULL),
    .package = "gdpins"
  )
  adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
  expect_s3_class(adapter, "gdpins_drive_adapter")
  expect_equal(adapter$kind, "real")
  expect_equal(adapter$root_id, "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
})

test_that("gdpins_real_drive() calls gdpins_ensure_drive_auth with GDRIVE_EMAIL by default", {
  auth_email <- NULL
  local_mocked_bindings(
    gdpins_ensure_drive_auth = function(email) { auth_email <<- email; invisible(NULL) },
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = "env@example.com"), {
    gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
  })
  expect_equal(auth_email, "env@example.com")
})

test_that("gdpins_real_drive() explicit email overrides GDRIVE_EMAIL", {
  auth_email <- NULL
  local_mocked_bindings(
    gdpins_ensure_drive_auth = function(email) { auth_email <<- email; invisible(NULL) },
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = "env@example.com"), {
    gdpins_real_drive(
      "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
      email = "explicit@example.com"
    )
  })
  expect_equal(auth_email, "explicit@example.com")
})

test_that("gdpins_real_drive() passes empty string when no email anywhere", {
  auth_email <- "sentinel"
  local_mocked_bindings(
    gdpins_ensure_drive_auth = function(email) { auth_email <<- email; invisible(NULL) },
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = ""), {
    gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
  })
  expect_equal(auth_email, "")
})

# ── Real adapter (skip unless live) ──────────────────────────────────────────

test_that("gdpins_real_drive() returns a gdpins_drive_adapter", {
  skip_on_ci()
  skip_if(
    nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")),
    "Skipping live Drive auth during R CMD check"
  )
  skip_if_offline()
  folder_id <- Sys.getenv("GDRIVE_TEST_FOLDER")
  skip_if(!nzchar(folder_id), "GDRIVE_TEST_FOLDER not set")
  gdpins_ensure_drive_auth()
  adapter <- gdpins_real_drive(folder_id)
  expect_s3_class(adapter, "gdpins_drive_adapter")
  expect_equal(adapter$kind, "real")
  expect_equal(adapter$root_id, folder_id)
})

# ── Phase 1: drive_id column + fake get_id() ─────────────────────────────────

test_that("gd_ls() fake adapter: drive_id column is NA_character_ for all entries", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".csv")
  writeLines("a,b\n1,2", local_tmp)
  gd_mkdir(adapter, "subdir")
  gd_upload(adapter, local_tmp, "data.csv")

  result <- gd_ls(adapter, recursive = TRUE)
  expect_true("drive_id" %in% names(result))
  expect_type(result$drive_id, "character")
  expect_true(all(is.na(result$drive_id)))
})

test_that("gd_ls() empty path returns 6-column tibble including drive_id", {
  adapter <- gdpins_fake_drive()
  result  <- gd_ls(adapter, "empty_path_xyz")
  expect_named(result, c("path", "is_dir", "size", "md5", "mtime", "drive_id"))
  expect_equal(nrow(result), 0L)
  expect_type(result$drive_id, "character")
})

test_that("fake adapter get_id() returns NA_character_", {
  adapter <- gdpins_fake_drive()
  expect_identical(adapter$get_id("any/path"),    NA_character_)
  expect_identical(adapter$get_id(""),            NA_character_)
  expect_identical(adapter$get_id("deeply/nested/file.csv"), NA_character_)
})

test_that("gd_ls() non-standard filenames: drive_id is NA for fake adapter", {
  adapter   <- gdpins_fake_drive()
  local_tmp <- tempfile(fileext = ".csv")
  writeLines("x,y\n1,2", local_tmp)
  # Files with spaces, parentheses, and special chars
  gd_upload(adapter, local_tmp, "my data (2024).csv")
  gd_upload(adapter, local_tmp, "report - final v2.csv")

  result <- gd_ls(adapter, recursive = FALSE)
  expect_true("drive_id" %in% names(result))
  expect_true(all(is.na(result$drive_id)))
  expect_true(any(grepl("my data", result$path, fixed = TRUE)))
})
