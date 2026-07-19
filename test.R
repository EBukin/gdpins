library(gdpins)

.priv_root <- Sys.getenv("OD_PRIV_ROOT")
.data_folder <- "kazLandEconImpact-data"
.data_root <- here::here(.priv_root, .data_folder)
drive_root <- gdpins_real_drive("1pjtAA9fzVOzVsz2NaEDtlJcYXZCpeKj4")
bd_interm <- gdpins_init_board(
  name = "data_interm",
  local_dir = file.path(.data_root, "data-interm"),
  drive_path = "data-interm",
  cache_dir = file.path(.data_root, "data-interm-cache"),
  versioned = TRUE,
  create = NA,
  on_discrepancy = NULL,
  adapter = drive_root
)

gdpins_pin_read(board = bd_interm, name = "geom-adm2")
# gdpins_pin_path(board = bd_interm, name = "geom-adm1-90")

# gdpins_pin_read(board = bd_interm, name = "geom-adm1-90")

gdpins_pin_path(board = bd_interm, name = "geom-adm1-90") |>
  nanoparquet::read_parquet()
arrow::open_dataset() |>
  dplyr::collect() |>
  gdpins::gdpins_as_sf()
