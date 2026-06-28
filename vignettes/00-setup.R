# Setup script for kazThesis analysis
# This script loads essential libraries and sets up output directories

# Libraries ---------------------------------------------------------------
pacman::p_load(
  "dplyr",
  # Data reading and wrangling
  "tidyr",
  "stringr",
  "readr",
  "tibble",
  "purrr",
  "lubridate",
  "forcats",
  # Data management
  "arrow",
  "pins",
  "googledrive",
  "gargle",
  # Spatial data
  "sf",
  # Visualization
  "ggplot2",
  "patchwork",
  # Table output
  "flextable",
  # Utilities
  "glue",
  "here",
  "knitr",
  "kableExtra"
)

# Load gdpins (package-in-place) ------------------------------------------

pkgload::load_all(here::here())

# Knitr options -----------------------------------------------------------

knitr::opts_chunk$set(
  warning = FALSE,
  message = FALSE,
  error   = FALSE
)

# Project data root -------------------------------------------------------

# All project data lives under $OD_PRIV_ROOT/kazLandEconImpact-data/
# This constant mirrors the Google Drive folder name exactly (ADR §3).
.priv_root   <- Sys.getenv("OD_PRIV_ROOT")
.data_folder <- "kazLandEconImpact-data"
.data_root   <- here::here(.priv_root, .data_folder)
dir.create(.data_root, recursive = TRUE, showWarnings = FALSE)

# gdpins boards -----------------------------------------------------------
#
# Three pins boards + raw-exogenous connection, matching ADR §3 layout:
#
#   $OD_PRIV_ROOT/kazLandEconImpact-data/
#     raw-exogenous/          <- plain mirror of Drive raw-exogenous/
#     data-raw-cache/         <- cache of Drive data-raw/  (pins board)
#     data-interm-cache/      <- cache of Drive data-interm/
#     data-clean-cache/       <- cache of Drive data-clean/
#     output/tables/          <- local output tables (published to Drive)
#     output/figures/         <- local output figures (published to Drive)

bd_raw <- gdpins_init_board(
  name           = "data_raw",
  drive_path     = paste0(.data_folder, "/data-raw"),
  cache_dir      = file.path(.data_root, "data-raw-cache"),
  versioned      = TRUE,
  create         = NA,
  on_discrepancy = NULL
)

bd_interm <- gdpins_init_board(
  name           = "data_interm",
  drive_path     = paste0(.data_folder, "/data-interm"),
  cache_dir      = file.path(.data_root, "data-interm-cache"),
  versioned      = TRUE,
  create         = NA,
  on_discrepancy = NULL
)

bd_clean <- gdpins_init_board(
  name           = "data_clean",
  drive_path     = paste0(.data_folder, "/data-clean"),
  cache_dir      = file.path(.data_root, "data-clean-cache"),
  versioned      = TRUE,
  create         = NA,
  on_discrepancy = NULL
)

bd_output <- gdpins_init_board(
  name           = "output_tables",
  drive_path     = paste0(.data_folder, "/output-tables"),
  cache_dir      = file.path(.data_root, "output", "tables"),
  versioned      = FALSE,
  create         = NA,
  on_discrepancy = NULL
)

# Raw-exogenous connection ------------------------------------------------
#
# Plain-file mirror for data as received from APIs / external sources.
# Sub-folders by source (e.g. worldbank-api/, kadaster/).

conn_raw <- gdpins_raw_connect(
  drive_path     = paste0(.data_folder, "/raw-exogenous"),
  local_path     = file.path(.data_root, "raw-exogenous"),
  create         = NA,
  on_discrepancy = NULL
)

# Convenience wrappers (project-level thin shims) -------------------------
#
# These are NOT part of the reusable gdpins package (ADR §5.2 note).
# They bind a fixed board so analysis scripts stay terse.

#' Read a pin from the data-raw board
read_raw <- function(name, version = NULL) {
  gdpins_pin_read(bd_raw, name, version = version)
}

#' Write a pin to the data-raw board
write_raw <- function(x, name) {
  gdpins_pin_write(bd_raw, x, name)
}

#' Read a pin from the data-interm board
read_interm <- function(name, version = NULL) {
  gdpins_pin_read(bd_interm, name, version = version)
}

#' Write a pin to the data-interm board
write_interm <- function(x, name) {
  gdpins_pin_write(bd_interm, x, name)
}

#' Read a pin from the data-clean board
read_clean <- function(name, version = NULL) {
  gdpins_pin_read(bd_clean, name, version = version)
}

#' Write a pin to the data-clean board
write_clean <- function(x, name) {
  gdpins_pin_write(bd_clean, x, name)
}

#' Read a pin from the output-tables board
read_output <- function(name, version = NULL) {
  gdpins_pin_read(bd_output, name, version = version)
}

#' Write a pin to the output-tables board
write_output <- function(x, name) {
  gdpins_pin_write(bd_output, x, name)
}

# Output directories -------------------------------------------------------

output_dir  <- here::here("output")
tables_dir  <- file.path(.data_root, "output", "tables")
figures_dir <- here::here("output", "figures")

for (.d in c(output_dir, tables_dir, figures_dir)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE)
}

# ggplot theme setup -------------------------------------------------------

# Set default theme with larger text
theme_set(theme_minimal(base_size = 14))

# Helper functions ---------------------------------------------------------

here("analysis", "00-fn-generic.R")        |> source(echo = FALSE)
here("analysis", "00-fn-recoding.R")       |> source(echo = FALSE)
here("analysis", "00-fn-reg.R")            |> source(echo = FALSE)
here("analysis", "00-fn-kazsub-extract.R") |> source(echo = FALSE)
