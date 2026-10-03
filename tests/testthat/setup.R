# Keep default board caches out of the real user home during tests.
withr::local_options(
  gdpins.cache_dir = file.path(tempdir(), "gdpins-test-cache"),
  .local_envir = teardown_env()
)
