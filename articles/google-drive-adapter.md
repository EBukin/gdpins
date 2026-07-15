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
#> Warning: ! "test_board": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.
board
#> <gdpins_board> [DC-] v+ cfg=drive_cache name=test_board path=project/data-raw
#> config: "drive_cache"
#> name: "test_board"
#> versioned: "TRUE"
#> drive: "project/data-raw"
#> cache: "/tmp/RtmpLFZGtB/cache_2aeb61da65b2"
```

The fake adapter mirrors Drive operations on the local filesystem — no
credentials, no network, fully reproducible.

Note that
[`gdpins_fake_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_fake_drive.md)
is a **test seam**, not an offline-mode substitute: it starts from an
empty tempdir, so swapping it in for
[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
on a board or connection you have already been working with will not
preserve the existing Drive-side layout, and typically surfaces as
create-confirm errors. To temporarily disconnect a real board or
connection from Drive, see “Deliberately going offline and back online”
below instead.

## Deliberately going offline and back online

[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
and
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
fall back to local-only automatically when Drive is unreachable (see the
“Offline behaviour” section of
[`vignette("gdpins-usage")`](https://ebukin.github.io/gdpins/articles/gdpins-usage.md)).
Sometimes you want the same effect on purpose — for example, Drive is
flaky, you are working on a plane, or you just don’t want network calls
slowing down every read/write for a while.

[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
detaches Drive from an already-connected board or raw connection,
without touching any files:

``` r

adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "project/data-raw",
  cache_dir  = tempfile("cache_"),
  local_dir  = tempfile("local_"),
  adapter    = adapter,
  create     = TRUE
)
#> Warning: ! "data_raw": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.

board_offline <- gdpins_go_offline(board)
#> ℹ Board "data_raw" switched to local-only (offline) mode.
#> ℹ Drive is untouched; call `gdpins_go_online()` to reconnect and sync.
board_offline$config   # "local_only"
#> [1] "local_only"

# Reads and writes stay local -- no network calls, no blocked writes
gdpins_pin_write(board_offline, mtcars, "cars")
#> Creating new version '20260715T125513Z-c0340'
#> Writing to pin 'cars'
gdpins_pin_read(board_offline, "cars")
#> # A tibble: 32 × 11
#>      mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>    <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>  1  21       6  160    110  3.9   2.62  16.5     0     1     4     4
#>  2  21       6  160    110  3.9   2.88  17.0     0     1     4     4
#>  3  22.8     4  108     93  3.85  2.32  18.6     1     1     4     1
#>  4  21.4     6  258    110  3.08  3.22  19.4     1     0     3     1
#>  5  18.7     8  360    175  3.15  3.44  17.0     0     0     3     2
#>  6  18.1     6  225    105  2.76  3.46  20.2     1     0     3     1
#>  7  14.3     8  360    245  3.21  3.57  15.8     0     0     3     4
#>  8  24.4     4  147.    62  3.69  3.19  20       1     0     4     2
#>  9  22.8     4  141.    95  3.92  3.15  22.9     1     0     4     2
#> 10  19.2     6  168.   123  3.92  3.44  18.3     1     0     4     4
#> # ℹ 22 more rows
```

Under the hood,
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
reuses whichever local storage the board already had — the standalone
`local_dir`/`local_board` for a `"drive_cache_local"` board, or the
`cache_dir`/`cache_board` for a `"drive_cache"` board with no standalone
local directory (mirroring the automatic offline fallback). Nothing is
copied or deleted; the returned object just stops touching Drive. The
original Drive configuration travels with the returned object, so
[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
can restore it later:

``` r

# Later, once Drive is reachable again:
board_online <- gdpins_go_online(
  board_offline,
  on_discrepancy = "sync_to_drive"   # push what changed while offline
)
board_online$config   # back to "drive_cache_local"
```

[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
requires
[`gdpins_is_online()`](https://ebukin.github.io/gdpins/reference/gdpins_is_online.md)
to be `TRUE` and errors if `x` was never produced by
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
— it restores a *specific* prior connection rather than guessing at one.
`on_discrepancy` takes the same values as
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)/[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
(`"prompt"`, `"warn"`, `"sync_from_drive"`, `"sync_to_drive"`,
`"ignore"`), so you control exactly how offline changes get reconciled
with Drive. If your Drive credentials expired while offline, pass a
freshly authenticated adapter:
`gdpins_go_online(board_offline, adapter = gdpins_real_drive("folder-id"))`.

The same two functions work on raw connections
([`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md))
the same way — `gdpins_go_offline(conn)` / `gdpins_go_online(conn)`.
