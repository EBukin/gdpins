# gdpins

**Google Drive + pins data management for R projects.**

`gdpins` layers three storage models over Google Drive for reproducible,
offline-capable data pipelines. Drive is the source of truth; a local
cache mirrors it. Reads are local-first; writes fan out to Drive and
cache simultaneously; sync and delete are always explicit and guarded.

## Storage layers

| Layer | Interface | Use |
|----|----|----|
| **Pins boards** | `gdpins_pin_*` | Versioned R objects: tibbles, sf, nested lists |
| **Raw-exogenous connection** | `gdpins_raw_*` | Plain files as received from APIs/sources |
| **Output** | `gdpins_save_figure`, `gdpins_publish_output` | Local-first figures/tables, published to Drive deliberately |

## Installation

Install from GitHub:

``` r

# install.packages("pak")
pak::pak("EBukin/gdpins")
```

Or load in-place from the project root:

``` r

pkgload::load_all(".")
```

## Authentication

Set your Google account email in `.Renviron`:

    GDRIVE_EMAIL=you@example.com

Auth is lazy — triggered on the first Drive operation, or call
explicitly:

``` r

gdpins_ensure_drive_auth()
gdpins_is_online()   # check connectivity
```

Offline and local-only workflows need no auth.

## Boards

A board wraps one layer of the data pipeline. Three configurations:

``` r

# Local only — no Drive, works fully offline
bd_local <- gdpins_init_board(
  name      = "scratch",
  local_dir = "path/to/local/folder"
)

# Drive + cache — standard production configuration
bd_raw <- gdpins_init_board(
  name           = "data_raw",
  drive_path     = "my-project-data/data-raw",
  cache_dir      = "path/to/data-raw-cache",
  versioned      = TRUE,
  create         = NA,        # prompt to create if Drive folder absent
  on_discrepancy = "prompt"   # "warn" for non-interactive scripts
)

# Drive + cache + standalone local (super config)
bd_clean <- gdpins_init_board(
  name       = "data_clean",
  drive_path = "my-project-data/data-clean",
  cache_dir  = "path/to/data-clean-cache",
  local_dir  = "path/to/data-clean-local",
  versioned  = TRUE
)
```

Pin names are **bare snake_case** — the board encodes the pipeline
layer.

``` r

# Write any R object — tibble, sf, list, nested tibble
gdpins_pin_write(bd_raw, gdp_tbl,  "gdp_panel")
gdpins_pin_write(bd_raw, parcels,  "parcels")   # sf auto-encoded as parquet

# Read back
gdp_panel <- gdpins_pin_read(bd_raw, "gdp_panel")
parcels   <- gdpins_pin_read(bd_raw, "parcels")  # sf restored with CRS intact
```

## Raw-exogenous connection

For data as received from external sources — plain files, no pins
metadata.

``` r

conn <- gdpins_raw_connect(
  drive_path = "my-project-data/raw-exogenous/worldbank-api",
  local_path = "path/to/raw-exogenous/worldbank-api",
  create     = TRUE
)

# Store an R object (serialised by extension: .parquet, .csv, .rds, .geojson)
gdpins_raw_put_object(conn, api_tbl, "gdp_2024.parquet")

# Upload a file verbatim (byte-faithful — no R round-trip)
gdpins_raw_put_file(conn, path = "downloads/data.geojson", name = "data.geojson")

# Retrieve (reads local mirror; hits Drive only if absent locally)
result <- gdpins_raw_get(conn, "gdp_2024.parquet")

# List contents
gdpins_raw_ls(conn, depth = 2)
```

## Sync

Sync is **always explicit** — never automatic.

``` r

# Auto: newer side wins, both directions
gdpins_sync(bd_raw)

# Explicit direction
gdpins_sync(bd_raw, direction = "from_drive")   # pull Drive → local
gdpins_sync(bd_raw, direction = "to_drive")     # push local → Drive

# Check drift first
gdpins_board_status(bd_raw)   # in_sync / local_ahead / drive_ahead / offline
```

For versioned boards, conflicts create new versions (zero data loss).
For raw or unversioned boards, conflicts prompt interactively or stop
with a report. Nothing is silently overwritten.

## Discovery and output

``` r

gdpins_list_pins(bd_clean)          # tibble: name, type, n_versions, size
gdpins_pin_info(bd_clean, "parcels")

# Save a figure (PNG or SVG — ggplot object is not stored)
gdpins_save_figure(plot = p, name = "gdp_trend", dir = "output/figures",
                   width = 8, height = 5)

# Publish local output to Drive (always deliberate — dry_run = TRUE first)
gdpins_publish_output(
  tables_board  = bd_output,
  figures_dir   = "output/figures",
  drive_tables  = "output-tables",
  drive_figures = "output-figures",
  dry_run       = TRUE
)
```

## Pruning old versions

``` r

# Preview (dry_run = TRUE is the default)
gdpins_prune_pin_versions(bd_raw, "gdp_panel", keep = 3, dry_run = TRUE)

# Actually prune (trash on Drive, not hard delete)
gdpins_prune_board_versions(bd_raw, keep = 2, dry_run = FALSE, force = TRUE)
```

## Data flow

    API/source  ──►  raw-exogenous  ──►  data-raw  ──►  data-interm  ──►  data-clean
      (gdpins_raw_*)                      (gdpins_pin_write / gdpins_pin_read)
                                                                              │
                                           output-tables board + output-figures folder
                                                    (gdpins_publish_output)

A concept (`parcels`, `gdp_panel`) keeps its name as it flows
`raw → interm → clean`; the board encodes the layer.

## Geospatial encoding

`sf` objects are stored as parquet with geometry columns encoded as WKT
and the CRS (EPSG code) embedded in the column name (`geom__4326__`).
The round-trip is lossless — CRS and geometry are restored automatically
on read.

``` r

gdpins_sf_to_parquet(sf_obj)   # df with WKT geometry columns
gdpins_parquet_to_sf(df)       # sf with original CRS restored
```

### WKT engine

The geometry ↔︎ WKT conversion uses one of two interchangeable engines,
chosen with the `wkt_engine` / `engine` argument or the
`gdpins.wkt_engine` option:

- `"wk"` (**default**) — uses the
  [wk](https://paleolimbot.github.io/wk/) package. ~20× faster to write
  than `sf` and always full-precision.
- `"sf"` — uses
  [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
  (pinned to `digits = 15`, so also full-precision). A dependency-light
  fallback.

Both are read-compatible: WKT written by one engine reads back correctly
with the other, so you can switch at any time without re-encoding stored
data.

``` r

gdpins_pin_write(board, sf_obj, "parcels")                    # default "wk"
gdpins_pin_write(board, sf_obj, "parcels", wkt_engine = "sf") # force sf
options(gdpins.wkt_engine = "sf")                             # switch globally
```

> Note: a bare
> [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
> defaults to 7 significant digits, silently rounding projected
> coordinates (e.g. UTM metres) by up to ~0.5 m. gdpins avoids this on
> both engines. A benchmark harness lives in
> `tests/testthat/test-benchmark-wkt.R` (skipped unless
> `GDPINS_BENCH_WKT=true`).

## Testing

Unit tests use a fake Drive adapter and run without authentication or
network:

``` r

testthat::test_package("gdpins")
```

Live tests run against a real Google Drive folder and are skipped by
default. To run them:

``` powershell
$env:GDRIVE_TEST_FOLDER = "<your-test-folder-id>"
Rscript --no-init-file -e 'testthat::test_file("tests/testthat/test-live.R")'
```

## License

MIT — see [LICENSE](https://ebukin.github.io/gdpins/LICENSE).
