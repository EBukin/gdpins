# Getting Started with gdpins

`gdpins` is a package that layers **Google Drive + pins** for
reproducible, offline-capable data management. Drive is the source of
truth; a local cache mirrors it. Reads are local-first; writes fan out;
sync and delete are explicit and guarded.

## Installation

`gdpins` is a package-in-place — load it from the project root:

``` r

pkgload::load_all(".")
# or, once installed:
# library(gdpins)
```

## Authentication

Drive operations use lazy, CLI-guided auth. Set your email once in
`.Renviron`:

    GDRIVE_EMAIL=you@example.com

Check connectivity:

``` r

gdpins_is_online()
```

## Drive adapter

All Drive operations go through an adapter. Create one with
[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
by supplying your **project root folder ID** (visible in the folder’s
Drive URL):

    https://drive.google.com/drive/folders/<your-folder-id-here>

``` r

# Picks up GDRIVE_EMAIL by default:
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")

# Or a path string (resolved automatically via googledrive::drive_get):
adapter <- gdpins_real_drive("My Drive/kazLandEconImpact-data")

# Optional explicit override:
adapter <- gdpins_real_drive(
  "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
  email = "you@example.com"
)
```

Optional pre-flight auth call (usually unnecessary if you construct a
real adapter right away):

``` r

gdpins_ensure_drive_auth()
```

### Verify folder locations

Before wiring up boards, confirm you have the right folder:

``` r

# Returns a clickable browser URL for any folder in the adapter root
gdpins_drive_url(adapter)                              # root folder
gdpins_drive_url(adapter, "kazLandEconImpact-data/data-raw")  # subfolder
```

You can also pass a Drive folder ID directly as `drive_path` when you
know exactly which folder to use. `gdpins` verifies the folder exists
and errors if not — though by default that check happens when the board
is first used, not here; see [Lazy connection](#lazy-connection) below:

``` r

bd_raw <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456",  # folder ID directly
  cache_dir  = file.path(Sys.getenv("OD_PRIV_ROOT"), "data-raw-cache"),
  adapter    = adapter
)
```

## Board initialisation

A board wraps a layer of the data pipeline. Three configurations:

``` r

# Local only — no Drive, works fully offline (no adapter needed)
bd_local <- gdpins_init_board(
  name      = "scratch",
  local_dir = file.path(Sys.getenv("OD_PRIV_ROOT"), "scratch")
)
```

``` r

# Drive + cache — standard production configuration
bd_raw <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "kazLandEconImpact-data/data-raw",
  cache_dir  = file.path(Sys.getenv("OD_PRIV_ROOT"),
                         "kazLandEconImpact-data", "data-raw-cache"),
  adapter    = adapter,
  versioned  = TRUE,
  create     = NA,          # prompt to create if absent
  on_discrepancy = NULL     # "prompt" interactively / "warn" in scripts
)
```

``` r

# Drive + cache + standalone local (super config)
bd_clean <- gdpins_init_board(
  name       = "data_clean",
  drive_path = "kazLandEconImpact-data/data-clean",
  cache_dir  = file.path(Sys.getenv("OD_PRIV_ROOT"),
                         "kazLandEconImpact-data", "data-clean-cache"),
  local_dir  = file.path(Sys.getenv("OD_PRIV_ROOT"),
                         "kazLandEconImpact-data", "data-clean-local"),
  adapter    = adapter,
  versioned  = TRUE
)
```

## Lazy connection

The three chunks above cost nothing.
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
does no Drive work: it records what you asked for and connects the first
time you actually use the board. A script that sets up `bd_local`,
`bd_raw` and `bd_clean` but only ever reads from `bd_raw` pays for one
board, not three.

Connecting is what costs — the online probe, the Drive existence/create
check, resolving the folder ID, building the `pins` boards, and the
`on_discrepancy` sync check. It is triggered by the first verb that
touches board contents:
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md),
[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md),
and friends. Printing a board does *not* connect it.

``` r

gdpins_board_is_connected(bd_raw)   # FALSE — nothing has touched it yet

gdpins_pin_read(bd_raw, "parcels")  # connects, then reads
gdpins_board_is_connected(bd_raw)   # TRUE
```

The catch is that init-time errors move to first use: a mistyped
`drive_path`, a missing folder with `create = FALSE`, the `create = NA`
prompt, and the sync warning all surface later than they used to. When
you would rather find out immediately, connect on purpose:

``` r

# Force the Drive check and sync check now
gdpins_board_connect(bd_raw)

# ... or just for this connection, with a different discrepancy policy
gdpins_board_connect(bd_clean, on_discrepancy = "sync_from_drive")
```

To opt out entirely, per board or globally:

``` r

bd_raw <- gdpins_init_board(name = "data_raw", drive_path = "...",
                            cache_dir = "...", adapter = adapter,
                            lazy = FALSE)

options(gdpins.lazy_boards = FALSE)   # every board, this session
```

See
[`?"lazy-boards"`](https://ebukin.github.io/gdpins/reference/lazy-boards.md)
for the full picture.

## Writing and reading pins

Pin names are **bare snake_case** — the board encodes the layer.

``` r

library(dplyr)

# Any R object — tibble, sf, list, nested tibble
gdpins_pin_write(bd_raw, my_tibble, "gdp_panel")
gdpins_pin_write(bd_raw, my_sf,     "parcels")    # sf auto-encoded as parquet
```

``` r

gdp_panel <- gdpins_pin_read(bd_raw, "gdp_panel")
parcels   <- gdpins_pin_read(bd_raw, "parcels")   # sf decoded with CRS intact
```

``` r

# Remove a pin across all configured board layers (idempotent if missing)
gdpins_pin_remove(bd_raw, "gdp_panel")
```

## Format selection

`gdpins` auto-detects the storage format via
[`gdpins_detect_format()`](https://ebukin.github.io/gdpins/reference/gdpins_detect_format.md).
The rules, in order:

| Object type | Chosen format | Storage |
|----|----|----|
| Not a data frame (list, model, …) | `"rds"` | [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) |
| Data frame with list-columns (non-sf) | `"rds"` | [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) |
| Plain tibble / data frame | `"parquet"` | Parquet via `nanoparquet` |
| `sf` object (all list-cols are `sfc`) | `"parquet"` | Parquet (geometry WKT-encoded) |

``` r

gdpins_detect_format(mtcars)         # "parquet"  — plain data frame
gdpins_detect_format(my_sf)          # "parquet"  — sf, sfc cols are fine
gdpins_detect_format(my_model)       # "rds"    — not a data frame
gdpins_detect_format(nested_tibble)  # "rds"    — has non-sfc list-column
```

Override the format explicitly when you need to:

``` r

# Force RDS — useful for tibbles with custom attributes you want to preserve
gdpins_pin_write(bd_raw, my_tibble, "gdp_panel", format = "rds")

# Force Parquet — rarely needed; auto-detect handles most cases
gdpins_pin_write(bd_raw, my_tibble, "gdp_panel", format = "parquet")
```

> **Rule of thumb:** let auto-detection choose. Override to `"rds"` only
> if the object has list-columns with non-spatial content (e.g. nested
> model output) that you want to read back in R without re-building.

## Spatial data (sf) round-trip

`sf` objects are stored as **Parquet** with geometry converted to WKT
text. CRS (EPSG code) is embedded in the column name using the suffix
`__<epsg>__`:

    geometry column "geometry" with EPSG 4326
      → stored as column "geometry__4326__" (WKT text)
      → restored as column "geometry" (sfc) with CRS 4326 on read

All of this happens automatically — no manual encoding/decoding needed:

``` r

# Write sf — geometry and CRS encoded automatically
gdpins_pin_write(bd_raw, parcels_sf, "parcels")

# Read back — sf class and CRS fully restored
parcels <- gdpins_pin_read(bd_raw, "parcels")
sf::st_crs(parcels)$epsg  # original EPSG

# Multiple geometry columns with different CRS are each encoded separately
gdpins_pin_write(bd_raw, multi_geom_sf, "parcels_multi")
```

The helpers
[`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
and
[`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md)
are exposed if you need to encode/decode manually (e.g. to write to an
external Parquet file):

``` r

encoded <- gdpins_sf_to_parquet(parcels_sf)   # tibble with geometry__4326__ col
restored <- gdpins_parquet_to_sf(encoded)      # sf with CRS restored
```

> **Limitation:** geometry columns must have an EPSG integer CRS. Custom
> proj-string-only CRS will error. Set a CRS first with
> [`sf::st_set_crs()`](https://r-spatial.github.io/sf/reference/st_crs.html).

### Keeping geometry as WKT text (`wkt_engine = "none"`)

Sometimes you want the geometry back as raw WKT text — to inspect it,
hand it to another tool, or skip the cost of building an `sf` object.
Pass `wkt_engine = "none"` to
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md):
the geometry columns come back as character vectors, their names still
carrying the `__<epsg>__` suffix.

[`gdpins_as_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_as_sf.md)
converts such a data frame back to `sf`. It autodetects the geometry
column (a character column named like `geom__4326__`, `geom`, or `wkt`)
and infers the CRS from the name — trusting the standard `__<epsg>__`
pattern silently, using a non-standard digit run (`geom_1111`) with a
message, and falling back to `default_epsg` with a warning when the name
has no digits. Pass `epsg` (and `column`, if several candidates match)
to be explicit.

``` r

txt <- gdpins_pin_read(bd_raw, "parcels", wkt_engine = "none")
class(txt)                # a plain tibble; geometry is WKT text

parcels_again <- gdpins_as_sf(txt)           # autodetect column + EPSG
sf::st_crs(parcels_again)$epsg

# Firmly set the CRS when the column name does not encode it
df <- data.frame(geom = "POINT (0 0)")
gdpins_as_sf(df, epsg = 4326)
```

### Choosing the WKT engine

The geometry ↔︎ WKT conversion is done by one of two interchangeable
engines:

- `"wk"` (**default**) — the [wk](https://paleolimbot.github.io/wk/)
  package. About 20× faster to write than `sf`, and full-precision.
- `"sf"` —
  [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html),
  pinned to `digits = 15` so it is also full-precision. A
  dependency-light fallback.

Select per call with `wkt_engine` (on
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md)
/
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
/
[`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md)
/
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md))
or `engine` (on the two helpers), or set the default for the whole
session:

``` r

# Per-call override
gdpins_pin_write(bd_raw, parcels_sf, "parcels", wkt_engine = "sf")

# Session-wide default
options(gdpins.wkt_engine = "sf")

encoded_sf <- gdpins_sf_to_parquet(parcels_sf, engine = "sf")
```

Both engines are **read-compatible**: WKT written by one reads back
correctly with the other, so switching engines never requires
re-encoding stored data.

> **Precision note:** a bare
> [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
> uses `getOption("digits")` (7 significant figures), which silently
> rounds projected coordinates (e.g. UTM metres) by up to ~0.5 m. gdpins
> avoids this on **both** engines — the `"wk"` engine is exact by
> construction, and the `"sf"` engine is called with `digits = 15`.

## Reading a specific version

When `versioned = TRUE` (the default), each
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md)
call creates a new version rather than overwriting. Versions are
labelled by timestamp.

``` r

# Inspect all versions of a pin
info <- gdpins_pin_info(bd_raw, "gdp_panel")
info$versions        # tibble: version label, created, size
info$n_versions      # integer count
```

``` r

# Read the latest version (default)
gdpins_pin_read(bd_raw, "gdp_panel")

# Read a specific historical version by its label
gdpins_pin_read(bd_raw, "gdp_panel", version = "20240615T120000Z-abc12")
```

``` r

# Keep only the 3 most recent versions, dry-run first
gdpins_prune_pin_versions(bd_raw, "gdp_panel", keep = 3, dry_run = TRUE)
gdpins_prune_pin_versions(bd_raw, "gdp_panel", keep = 3, dry_run = FALSE)
```

> For a `versioned = FALSE` board, each write **overwrites** the
> previous value. Use this for frequently-updated reference data where
> history is unwanted.

## Offline behaviour

When Drive is unreachable (no internet, VPN down), a board falls back
automatically as it connects:

| Config              | Offline behaviour                                 |
|---------------------|---------------------------------------------------|
| `local_only`        | Fully offline — no change                         |
| `drive_cache`       | Falls back to cache directory as local-only board |
| `drive_cache_local` | Falls back to standalone `local_dir` board        |

A warning is emitted; writes are blocked (Drive boards are
write-protected offline); reads continue from the local copy.

``` r

# Check connectivity explicitly before Drive operations
gdpins_is_online()   # TRUE / FALSE

# Board status shows sync state between Drive and local
gdpins_board_status(bd_raw)

# Reads work offline — served from cache or local_dir
gdp_panel <- gdpins_pin_read(bd_raw, "gdp_panel")  # no network needed
```

The fallback above is automatic and happens only when Drive is
unreachable at init time. To *deliberately* detach an already-connected
board or raw connection from Drive — e.g. to avoid network calls for a
while, or to keep working through a flaky connection — use
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
and
[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
instead. See “Deliberately going offline and back online” in
[`vignette("google-drive-adapter")`](https://ebukin.github.io/gdpins/articles/google-drive-adapter.md)
for details.

## Raw-exogenous connection

For data as received from APIs — plain files, no pins metadata.

``` r

conn <- gdpins_raw_connect(
  drive_path = "kazLandEconImpact-data/raw-exogenous/worldbank-api",
  local_path = file.path(Sys.getenv("OD_PRIV_ROOT"),
                         "kazLandEconImpact-data", "raw-exogenous",
                         "worldbank-api"),
  adapter    = adapter,
  create     = TRUE
)
```

``` r

# Store an R object (serialised to the appropriate format by extension)
gdpins_raw_put_object(conn, api_response_tbl, "gdp_2024.parquet")

# Upload a file verbatim (byte-faithful, any extension)
gdpins_raw_put_file(conn, path = "downloads/kadaster_raw.geojson",
                    name = "kadaster_raw.geojson")

# Retrieve (reads from local mirror; Drive only if absent locally)
gdp_raw  <- gdpins_raw_get(conn, "gdp_2024.parquet")
kad_raw  <- gdpins_raw_get(conn, "kadaster_raw.geojson")

# List contents — 8-column tibble including local paths and Drive IDs
listing <- gdpins_raw_ls(conn, depth = 2)
# listing$local_path  — absolute path on this machine
# listing$drive_id    — Drive file/folder ID (NA on fake adapter)
# listing$drive_url   — clickable browser URL (NA on fake adapter)

# Resolve a file to its local path, downloading from Drive if needed
local_path <- gdpins_raw_path(conn, "gdp_2024.parquet")
arrow::read_parquet(local_path)  # pass to any reader

# Non-standard filenames (spaces, parentheses) work too
gdpins_raw_path(conn, "quarterly report (Q1 2024).csv")

# Remove one file (flat or nested path). Missing files are ignored.
gdpins_raw_remove(conn, "kadaster_raw.geojson")
```

## Sync

Sync is **always explicit** — never automatic.

``` r

# Auto: newer side wins, both directions
gdpins_sync(bd_raw)

# Explicit direction
gdpins_sync(bd_raw, direction = "from_drive")   # pull Drive → local
gdpins_sync(bd_raw, direction = "to_drive")     # push local → Drive

# Check status first
gdpins_board_status(bd_raw)
```

Conflict handling for versioned boards: both sides simply become new
versions (zero data loss). For raw/unversioned boards:
`on_conflict = "stop"` halts and reports; `"prompt"` asks per conflict.

## Discovery

``` r

# List all pins
gdpins_list_pins(bd_clean)

# Detailed info for one pin
gdpins_pin_info(bd_clean, "parcels")
```

## Output

``` r

library(ggplot2)

# Save a figure (PNG or SVG — ggplot object is NOT stored)
gdpins_save_figure(
  plot   = ggplot(gdp_panel, aes(year, value)) + geom_line(),
  name   = "gdp_trend",
  dir    = here::here("output", "figures"),
  width  = 8,
  height = 5,
  device = "png"
)

# Write output table to output board
gdpins_pin_write(bd_output, summary_tbl, "regional_summary")

# Publish local output to Drive (deliberate final step)
gdpins_publish_output(
  tables_board  = bd_output,
  figures_dir   = here::here("output", "figures"),
  drive_tables  = "output-tables",
  drive_figures = "output-figures",
  adapter       = adapter,
  dry_run       = TRUE   # preview first
)

# Then actually publish:
gdpins_publish_output(
  tables_board  = bd_output,
  figures_dir   = here::here("output", "figures"),
  adapter       = adapter,
  dry_run       = FALSE
)
```

## Pruning old versions

``` r

# Preview what would be removed (dry_run = TRUE by default)
gdpins_prune_pin_versions(bd_raw, "gdp_panel", keep = 3, dry_run = TRUE)

# Actually prune
gdpins_prune_board_versions(bd_raw, keep = 2, dry_run = FALSE, force = TRUE)
```

## Console output

`gdpins` objects print compactly (≤80 cols):

``` r

print(bd_raw)
summary(bd_raw)
gdpins_list_pins(bd_raw)
gdpins_pin_info(bd_raw, "gdp_panel")
```

## Layered data flow

    API/source  ─►  raw-exogenous  ─►  data-raw  ─►  data-interm  ─►  data-clean
      (gdpins_raw_*)                    (gdpins_pin_write / gdpins_pin_read on each board)
                                                                            ▼
                                              output-tables board + output-figures folder
                                                       (gdpins_publish_output)

Pin names are bare snake_case. The board encodes the layer. A concept
keeps its name (`parcels`, `gdp_panel`) as it flows
`raw → interm → clean`, giving readable lineage without renaming.

See
[`docs/adr/0001-gdpins-data-architecture.md`](https://ebukin.github.io/gdpins/docs/adr/0001-gdpins-data-architecture.md)
for the full architectural decision record.

See also the **[Google Drive
Adapter](https://ebukin.github.io/gdpins/articles/google-drive-adapter.md)**
vignette for a deeper guide to adapter setup, folder ID lookup, and
[`gdpins_drive_url()`](https://ebukin.github.io/gdpins/reference/gdpins_drive_url.md).
