# helper-fixtures.R — shared test fixtures (contract §4)
# All fixtures are no-network. Each function returns a fresh object per call.

#' Plain tibble fixture
#' @keywords internal
fx_plain_tbl <- function() {
  tibble::tibble(
    id     = 1:5,
    name   = c("alpha", "beta", "gamma", "delta", "epsilon"),
    value  = c(1.1, 2.2, 3.3, 4.4, 5.5),
    flag   = c(TRUE, FALSE, TRUE, FALSE, TRUE)
  )
}

#' Tibble with a list-column fixture
#' @keywords internal
fx_list_col_tbl <- function() {
  tibble::tibble(
    id     = 1:3,
    label  = c("a", "b", "c"),
    data   = list(
      list(x = 1, y = 2),
      list(x = 3, y = 4),
      list(x = 5, y = 6)
    )
  )
}

#' Nested tibble fixture (tidyr::nest()-ed)
#' @keywords internal
fx_nested_tbl <- function() {
  base <- tibble::tibble(
    group = c("A", "A", "B", "B", "B"),
    x     = c(1, 2, 3, 4, 5),
    y     = c(10, 20, 30, 40, 50)
  )
  tidyr::nest(base, data = c(x, y))
}

#' Single-geometry sf fixture, EPSG 4326
#' @keywords internal
fx_sf_single <- function() {
  sf::st_sf(
    id       = 1:3,
    label    = c("point_a", "point_b", "point_c"),
    geometry = sf::st_sfc(
      sf::st_point(c(71.4, 51.2)),
      sf::st_point(c(76.9, 43.3)),
      sf::st_point(c(69.1, 41.3)),
      crs = 4326
    )
  )
}

#' Multi-geometry sf fixture with differing per-column CRS
#' @keywords internal
fx_sf_multi_crs <- function() {
  pts_4326 <- sf::st_sfc(
    sf::st_point(c(71.4, 51.2)),
    sf::st_point(c(76.9, 43.3)),
    crs = 4326
  )
  pts_3857 <- sf::st_transform(pts_4326, 3857)

  df <- tibble::tibble(
    id      = 1:2,
    label   = c("p1", "p2"),
    geom_wgs = pts_4326,
    geom_web = pts_3857
  )
  sf::st_sf(df)
}

#' Single-geometry sf fixture with non-4326 CRS (EPSG 3857)
#' @keywords internal
fx_sf_non4326 <- function() {
  pts <- sf::st_sfc(
    sf::st_point(c(7952102, 6686592)),
    sf::st_point(c(8560000, 5380000)),
    crs = 3857
  )
  sf::st_sf(
    id       = 1:2,
    label    = c("web_a", "web_b"),
    geometry = pts
  )
}

#' Projected-CRS polygon sf fixture (EPSG:32643, UTM 43N, metres)
#'
#' Coordinates carry sub-metre fractional parts on purpose: sf::st_as_text()
#' at its default 7 significant digits rounds these away, so this fixture
#' exercises the WKT-engine precision path.
#' @keywords internal
fx_sf_poly_utm <- function() {
  ring1 <- cbind(
    c(200000.123456, 200500.987654, 200500.111111, 200000.123456),
    c(1000000.654321, 1000000.222222, 1000500.999999, 1000000.654321)
  )
  ring2 <- cbind(
    c(300000.500001, 300500.250002, 300250.750003, 300000.500001),
    c(1200000.100004, 1200000.900005, 1200500.500006, 1200000.100004)
  )
  sf::st_sf(
    id       = 1:2,
    label    = c("parcel_a", "parcel_b"),
    geometry = sf::st_sfc(
      sf::st_polygon(list(ring1)),
      sf::st_polygon(list(ring2)),
      crs = 32643
    )
  )
}

#' Projected-CRS multipolygon sf fixture (EPSG:32643)
#' @keywords internal
fx_sf_multipoly_utm <- function() {
  p1a <- cbind(
    c(210000.123, 210300.456, 210300.789, 210000.123),
    c(1010000.321, 1010000.654, 1010300.987, 1010000.321)
  )
  p1b <- cbind(
    c(212000.111, 212300.222, 212300.333, 212000.111),
    c(1010000.444, 1010000.555, 1010300.666, 1010000.444)
  )
  p2a <- cbind(
    c(310000.777, 310300.888, 310300.999, 310000.777),
    c(1210000.101, 1210000.202, 1210300.303, 1210000.101)
  )
  sf::st_sf(
    id       = 1:2,
    label    = c("estate_a", "estate_b"),
    geometry = sf::st_sfc(
      sf::st_multipolygon(list(list(p1a), list(p1b))),
      sf::st_multipolygon(list(list(p2a))),
      crs = 32643
    )
  )
}

#' GeoJSON file fixture — writes to tempfile, returns path
#' @keywords internal
fx_geojson_path <- function() {
  tmp <- tempfile(fileext = ".geojson")
  sf_obj <- fx_sf_single()
  sf::st_write(sf_obj, tmp, quiet = TRUE)
  tmp
}

#' CSV file fixture — writes to tempfile, returns path
#' @keywords internal
fx_csv_path <- function() {
  tmp <- tempfile(fileext = ".csv")
  readr::write_csv(fx_plain_tbl(), tmp)
  tmp
}

#' Output summary table fixture
#' @keywords internal
fx_output_table <- function() {
  tibble::tibble(
    region     = c("Almaty", "Nur-Sultan", "Shymkent"),
    n_parcels  = c(12345L, 9876L, 7654L),
    mean_value = c(450.2, 720.5, 310.8),
    year       = 2023L
  )
}

#' ggplot fixture — returns a ggplot object (never stored)
#' @keywords internal
fx_ggplot <- function() {
  ggplot2::ggplot(fx_plain_tbl(), ggplot2::aes(x = id, y = value)) +
    ggplot2::geom_point() +
    ggplot2::labs(title = "Test figure")
}
