# Package index

## Board setup & auth

Initialise a pins board backed by Google Drive and manage credentials.

- [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
  : Initialise a gdpins board
- [`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md)
  : Connect a lazy board now
- [`gdpins_board_is_connected()`](https://ebukin.github.io/gdpins/reference/gdpins_board_is_connected.md)
  : Has a board connected yet?
- [`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)
  : Ensure Google Drive is authenticated
- [`gdpins_is_online()`](https://ebukin.github.io/gdpins/reference/gdpins_is_online.md)
  : Check whether an internet connection is available
- [`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
  : Report sync status of a board or raw connection
- [`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)
  : Synchronise a board or raw connection with Drive
- [`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
  [`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
  : Temporarily disconnect from Drive, then reconnect and sync later

## Pin read / write

Read and write versioned R objects (tibbles, sf, lists) to a board.

- [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
  : Read a pin from a gdpins board
- [`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
  : Resolve a pin to its file path(s) on disk
- [`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md)
  : Write a pin to a gdpins board
- [`gdpins_pin_info()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_info.md)
  : Retrieve detailed metadata for a single pin
- [`gdpins_list_pins()`](https://ebukin.github.io/gdpins/reference/gdpins_list_pins.md)
  : List all pins in a board
- [`gdpins_detect_format()`](https://ebukin.github.io/gdpins/reference/gdpins_detect_format.md)
  : Detect the appropriate storage format for an R object
- [`gdpins_pin_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_remove.md)
  : Remove a pin from a gdpins board

## Versioning & pruning

Manage historical versions stored on Drive and in the local cache.

- [`gdpins_prune_board_versions()`](https://ebukin.github.io/gdpins/reference/gdpins_prune_board_versions.md)
  : Prune old versions of all pins in a board
- [`gdpins_prune_pin_versions()`](https://ebukin.github.io/gdpins/reference/gdpins_prune_pin_versions.md)
  : Prune old versions of a single pin

## Raw-exogenous connection

Plain-file interface for API/source data that should not be pinned.

- [`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
  : Connect to a raw-exogenous Drive folder
- [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md)
  : List contents of a raw connection
- [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md)
  : Resolve a raw file to its absolute local path
- [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
  : Read a file from a raw connection
- [`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md)
  : Upload a file verbatim to a raw connection
- [`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md)
  : Write an R object to a raw connection
- [`gdpins_refresh_disconnect()`](https://ebukin.github.io/gdpins/reference/gdpins_refresh_disconnect.md)
  : Force-refresh a raw connection and disconnect
- [`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md)
  : Remove a file from a raw connection

## Output layer

Save figures and publish tabular output locally then to Drive.

- [`gdpins_save_figure()`](https://ebukin.github.io/gdpins/reference/gdpins_save_figure.md)
  : Save a ggplot figure to disk
- [`gdpins_publish_output()`](https://ebukin.github.io/gdpins/reference/gdpins_publish_output.md)
  : Publish local output to Google Drive

## Spatial helpers

Convert between sf objects and Parquet files.

- [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
  : Convert an sf object to a plain tibble suitable for parquet storage
- [`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md)
  : Restore an sf object from a parquet-encoded tibble
- [`gdpins_as_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_as_sf.md)
  : Convert a data frame with a WKT text column to an sf object
  (autodetecting)

## Package docs & methods

Package-level topics, S3 methods, and conceptual helper pages.

- [`auth`](https://ebukin.github.io/gdpins/reference/auth.md) :
  Authentication helpers for Google Drive
- [`board`](https://ebukin.github.io/gdpins/reference/board.md) : Board
  initialisation and S3 methods for gdpins_board
- [`` `$`( ``*`<gdpins_board>`*`)`](https://ebukin.github.io/gdpins/reference/board-extract.md)
  [`` `[[`( ``*`<gdpins_board>`*`)`](https://ebukin.github.io/gdpins/reference/board-extract.md)
  : Extract a field from a gdpins_board
- [`discovery`](https://ebukin.github.io/gdpins/reference/discovery.md)
  : Pin discovery and metadata
- [`format(`*`<gdpins_board>`*`)`](https://ebukin.github.io/gdpins/reference/format.gdpins_board.md)
  : Format a gdpins_board as a compact one-line string (≤80 cols)
- [`gdpins_drive_url()`](https://ebukin.github.io/gdpins/reference/gdpins_drive_url.md)
  : Return the Google Drive URL for a folder
- [`gdpins_fake_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_fake_drive.md)
  : Create a fake (tempdir-backed) Drive adapter
- [`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
  : Create a real Google Drive adapter
- [`io-formats`](https://ebukin.github.io/gdpins/reference/io-formats.md)
  : I/O format detection and geospatial encoding
- [`lazy-boards`](https://ebukin.github.io/gdpins/reference/lazy-boards.md)
  : Lazy board connection
- [`output`](https://ebukin.github.io/gdpins/reference/output.md) :
  Output rendering and Drive publishing
- [`print(`*`<gdpins_board>`*`)`](https://ebukin.github.io/gdpins/reference/print.gdpins_board.md)
  : Print a gdpins_board object (compact, ≤80 cols)
- [`print(`*`<gdpins_pin_info>`*`)`](https://ebukin.github.io/gdpins/reference/print.gdpins_pin_info.md)
  : Print method for gdpins_pin_info
- [`prune`](https://ebukin.github.io/gdpins/reference/prune.md) :
  Version pruning with delete guards
- [`raw-connection`](https://ebukin.github.io/gdpins/reference/raw-connection.md)
  : Raw-exogenous connection
- [`summary(`*`<gdpins_board>`*`)`](https://ebukin.github.io/gdpins/reference/summary.gdpins_board.md)
  : Summarise a gdpins_board object
- [`sync`](https://ebukin.github.io/gdpins/reference/sync.md) :
  Synchronisation engine
- [`verbs`](https://ebukin.github.io/gdpins/reference/verbs.md) :
  Read/write verbs for gdpins boards
