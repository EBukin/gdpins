# Setting up the Google Drive Adapter

``` r

library(gdpins)
```

## What is the Drive adapter?

The `gdpins` package isolates all Google Drive operations behind a
*Drive adapter* (`gdpins_drive_adapter`). Every function that touches
Drive — boards, raw connections, sync, publish — receives the adapter
rather than calling `googledrive` directly. This seam lets you swap a
real adapter for a fake (tempdir-backed) one in tests without any
network calls.

## Creating a real adapter

Use
[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
to create a real adapter. You must supply the **Drive folder ID** of
your project root folder — or a path string to look it up.

### Finding your folder ID

Open the folder in Google Drive in a browser. The URL looks like:

    https://drive.google.com/drive/folders/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms

The last segment is the folder ID.

### Creating the adapter

``` r

# Using a Drive folder ID (recommended):
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")

# Using a path string (resolved via googledrive::drive_get):
adapter <- gdpins_real_drive("My Drive/projects/myproject")
```

### Authentication and the `email` parameter

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
now calls
[`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)
automatically.

``` r

# 1) Uses GDRIVE_EMAIL from .Renviron (recommended)
adapter <- gdpins_real_drive("folder-id")

# 2) Explicit override
adapter <- gdpins_real_drive("folder-id", email = "explicit@example.com")

# 3) No email set -> gargle interactive CLI account picker
adapter <- gdpins_real_drive("folder-id", email = "")
```

Set this once in `~/.Renviron`:

``` txt
GDRIVE_EMAIL=you@example.com
```

An explicit pre-flight
[`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)
call is still valid, but optional when creating adapters with
[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md).

## Verifying the folder location

Use
[`gdpins_drive_url()`](https://ebukin.github.io/gdpins/reference/gdpins_drive_url.md)
to get a clickable URL for any folder within the adapter root:

``` r

# Root folder URL:
gdpins_drive_url(adapter)

# Subfolder URL:
gdpins_drive_url(adapter, "data-raw")
```

Copy-paste the URL into your browser to visually confirm the location
before connecting boards.

## Setting up a board

``` r

board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",   # relative to adapter root
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
board
```

You can also supply a Drive folder ID directly as `drive_path` — useful
when you know the exact folder ID:

``` r

board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter
)
```

When `drive_path` is a folder ID, `gdpins` verifies it exists and errors
immediately if not found. The `create` argument is ignored — folder IDs
cannot be auto-created.

## Setting up a raw connection

``` r

conn <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = "data/raw/worldbank-api",
  adapter    = adapter,
  create     = TRUE
)
conn
```

Nested uploads via
[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md)
and
[`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md)
create missing intermediate Drive folders automatically (for example
`"sub/sub/folder/file.rds"`).

## Removal behavior (full vs partial)

`gdpins` supports explicit, idempotent remove verbs:

``` r

# Boards: removes a pin from all configured board layers
gdpins_pin_remove(board, "cars")

# Raw connections: removes one file (flat or nested path)
gdpins_raw_remove(conn, "sub/sub/file.rds")
```

Drive removals are recoverable: files are moved to Drive trash (not
hard-deleted). For raw connections, removal scope is single files only;
recursive folder deletion is intentionally unsupported.

## Testing with a fake adapter

In scripts and packages, use
[`gdpins_fake_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_fake_drive.md)
for offline testing:

``` r

adapter <- gdpins_fake_drive()

board <- gdpins_init_board(
  name       = "test_board",
  drive_path = "project/data-raw",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
#> Warning: ! Board "test_board": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.
board
#> <gdpins_board> [DC-] v+ cfg=drive_cache name=test_board path=project/data-raw
#> config: "drive_cache"
#> name: "test_board"
#> versioned: "TRUE"
#> drive: "project/data-raw"
#> cache: "/tmp/RtmpEq24Xz/cache_24e278c496d4"
```

The fake adapter mirrors Drive operations on the local filesystem — no
credentials, no network, fully reproducible.
