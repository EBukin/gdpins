test_that("gdpins_ensure_drive_auth() no-ops when already authed", {
  local_mocked_bindings(
    .gd_has_token  = function() TRUE,
    .gd_drive_auth = function(email) stop("drive_auth must not be called"),
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = "user@example.com"), {
    expect_invisible(gdpins_ensure_drive_auth())
    expect_null(gdpins_ensure_drive_auth())
  })
})

test_that("gdpins_ensure_drive_auth() calls drive_auth when not authed", {
  auth_called_with <- NULL

  local_mocked_bindings(
    .gd_has_token  = function() FALSE,
    .gd_drive_auth = function(email) { auth_called_with <<- email; invisible(NULL) },
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = "user@example.com"), {
    expect_message(
      gdpins_ensure_drive_auth(),
      regexp = "Authenticating"
    )
  })
  expect_equal(auth_called_with, "user@example.com")
})

test_that("gdpins_ensure_drive_auth() forwards explicit email to drive_auth", {
  auth_called_with <- NULL

  local_mocked_bindings(
    .gd_has_token  = function() FALSE,
    .gd_drive_auth = function(email) { auth_called_with <<- email; invisible(NULL) },
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = ""), {
    suppressMessages(gdpins_ensure_drive_auth(email = "other@example.com"))
  })
  expect_equal(auth_called_with, "other@example.com")
})

test_that("gdpins_ensure_drive_auth() aborts when email is empty", {
  local_mocked_bindings(
    .gd_has_token  = function() FALSE,
    .gd_drive_auth = function(email) stop("must not reach drive_auth"),
    .package = "gdpins"
  )
  withr::with_envvar(c(GDRIVE_EMAIL = ""), {
    expect_error(
      gdpins_ensure_drive_auth(),
      regexp = "GDRIVE_EMAIL"
    )
  })
})

test_that("gdpins_is_online() returns TRUE when DNS resolves", {
  local_mocked_bindings(
    .nslookup_googleapis = function() "1.2.3.4",
    .package = "gdpins"
  )
  expect_true(gdpins_is_online())
})

test_that("gdpins_is_online() returns FALSE when DNS fails", {
  local_mocked_bindings(
    .nslookup_googleapis = function() NULL,
    .package = "gdpins"
  )
  expect_false(gdpins_is_online())
})

# ── Wrapper body coverage: mock at the dependency package level ───────────────

test_that(".gd_has_token() delegates to googledrive::drive_has_token", {
  local_mocked_bindings(
    drive_has_token = function() TRUE,
    .package = "googledrive"
  )
  expect_true(gdpins:::.gd_has_token())
})

test_that(".gd_drive_auth() delegates to googledrive::drive_auth", {
  auth_email <- NULL
  local_mocked_bindings(
    drive_auth = function(email) { auth_email <<- email; invisible(NULL) },
    .package = "googledrive"
  )
  gdpins:::.gd_drive_auth("test@example.com")
  expect_equal(auth_email, "test@example.com")
})

test_that(".nslookup_googleapis() delegates to curl::nslookup", {
  local_mocked_bindings(
    nslookup = function(host, error) "10.0.0.1",
    .package = "curl"
  )
  result <- gdpins:::.nslookup_googleapis()
  expect_equal(result, "10.0.0.1")
})
