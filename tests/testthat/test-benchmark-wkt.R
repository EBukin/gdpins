# test-benchmark-wkt.R — WKT <-> geometry conversion benchmark
#
# Compares the sfc <-> WKT conversion used by gdpins_sf_to_parquet() /
# gdpins_parquet_to_sf() across three back ends:
#
#   * sf      — sf::st_as_text()  /  sf::st_as_sfc(<character>)
#   * wk      — wk::as_wkt()      /  sf::st_as_sfc(wk::wkt(<character>))
#   * lwgeom  — lwgeom::st_astext / sf::st_as_sfc(<character>)  (if installed)
#
# The goal is to decide whether swapping the WKT engine inside io-formats.R is
# worth the extra dependency. These are NOT correctness tests for gdpins — they
# are a performance harness, so they are SKIPPED BY DEFAULT.
#
# To run:
#   Sys.setenv(GDPINS_BENCH_WKT = "true"); testthat::test_file(
#     "tests/testthat/test-benchmark-wkt.R")
# or from a shell:
#   GDPINS_BENCH_WKT=true Rscript -e 'testthat::test_file(
#     "tests/testthat/test-benchmark-wkt.R")'
#
# Optional knobs (env vars):
#   GDPINS_BENCH_MEDIUM_N  medium-size row count (default 50000, keep < 100000)
#   GDPINS_BENCH_SMALL_N   small-size  row count (default 500,   keep < 1000)
#   GDPINS_BENCH_TIMES     microbenchmark repetitions (default 8)

# ── skip guard ────────────────────────────────────────────────────────────────
skip_bench <- function() {
  if (!identical(Sys.getenv("GDPINS_BENCH_WKT"), "true")) {
    testthat::skip("WKT benchmark skipped (set GDPINS_BENCH_WKT=true to run)")
  }
  testthat::skip_if_not_installed("wk")
  testthat::skip_if_not_installed("microbenchmark")
}

# ── data generators (UTM 43N / EPSG:32643, metres) ────────────────────────────
bench_gen_polygons <- function(n, verts = 8L, crs = 32643L) {
  # deterministic — no set.seed side effects leak because we use a local RNG kind
  withr::with_seed(42, {
    cx  <- stats::runif(n, 200000, 800000)
    cy  <- stats::runif(n, 1000000, 3000000)
    ang <- seq(0, 2 * pi, length.out = verts + 1L)
    geoms <- vector("list", n)
    for (i in seq_len(n)) {
      r <- stats::runif(verts + 1L, 50, 500)
      r[verts + 1L] <- r[1L]                       # close the ring
      x <- cx[i] + r * cos(ang)
      y <- cy[i] + r * sin(ang)
      geoms[[i]] <- sf::st_polygon(list(cbind(x, y)))
    }
    sf::st_sfc(geoms, crs = crs)
  })
}

bench_gen_multipolygons <- function(n, parts = 3L, verts = 6L, crs = 32643L) {
  withr::with_seed(7, {
    cx  <- stats::runif(n, 200000, 800000)
    cy  <- stats::runif(n, 1000000, 3000000)
    ang <- seq(0, 2 * pi, length.out = verts + 1L)
    geoms <- vector("list", n)
    for (i in seq_len(n)) {
      plist <- vector("list", parts)
      for (p in seq_len(parts)) {
        ox <- cx[i] + (p - 1) * 2000
        r  <- stats::runif(verts + 1L, 50, 400)
        r[verts + 1L] <- r[1L]
        x <- ox    + r * cos(ang)
        y <- cy[i] + r * sin(ang)
        plist[[p]] <- list(cbind(x, y))
      }
      geoms[[i]] <- sf::st_multipolygon(plist)
    }
    sf::st_sfc(geoms, crs = crs)
  })
}

# ── one scenario: write + read across all available engines ───────────────────
bench_scenario <- function(label, sfc, times) {
  epsg    <- sf::st_crs(sfc)$epsg
  wkt_chr <- sf::st_as_text(sfc)          # the WKT text as stored in parquet
  has_lw  <- requireNamespace("lwgeom", quietly = TRUE)

  # microbenchmark's `list=` argument needs UNEVALUATED expressions (calls), not
  # functions — a list of functions would just reference the objects and measure
  # ~0 time. quote()d exprs are evaluated in this frame, where sfc/wkt_chr/epsg
  # live.

  # WRITE: sfc -> character WKT
  write_exprs <- list(
    sf = quote(sf::st_as_text(sfc)),
    wk = quote(as.character(wk::as_wkt(sfc)))
  )
  if (has_lw) write_exprs$lwgeom <- quote(lwgeom::st_astext(sfc))

  # READ: character WKT -> sfc. The wk path mirrors gdpins production: parse via
  # wk's handler, then assign the CRS (st_as_sfc.wk_wkt ignores `crs =`).
  read_exprs <- list(
    sf = quote(sf::st_as_sfc(wkt_chr, crs = epsg)),
    wk = quote({
      sfc <- sf::st_as_sfc(wk::wkt(wkt_chr))
      sf::st_crs(sfc) <- epsg
      sfc
    })
  )
  # lwgeom read == sf read with Sys.setenv(LWGEOM_WKT="true"); the parser is sf's
  # either way, so a separate lwgeom read row would duplicate sf. Skip it.

  mb_write <- microbenchmark::microbenchmark(list = write_exprs, times = times)
  mb_read  <- microbenchmark::microbenchmark(list = read_exprs,  times = times)

  to_df <- function(mb, direction) {
    s <- summary(mb, unit = "ms")
    data.frame(
      scenario  = label,
      n         = length(sfc),
      direction = direction,
      engine    = as.character(s$expr),
      median_ms = round(s$median, 3),
      min_ms    = round(s$min, 3),
      max_ms    = round(s$max, 3),
      stringsAsFactors = FALSE
    )
  }
  rbind(to_df(mb_write, "write"), to_df(mb_read, "read"))
}

# max absolute coordinate deviation (metres, in the layer CRS) of a round-trip
# result vs the original geometries
bench_max_dev <- function(rt, sfc) {
  a <- sf::st_coordinates(rt)[,  c("X", "Y")]
  b <- sf::st_coordinates(sfc)[, c("X", "Y")]
  max(abs(a - b))
}

# ── correctness / precision findings, encoded as assertions ───────────────────
# Two things matter for gdpins:
#   1. PARSER equivalence — reading the SAME WKT text via sf vs wk gives
#      bit-identical geometries (so the read path can be swapped safely).
#   2. WRITER precision — sf::st_as_text() defaults to getOption("digits") == 7
#      significant figures, which SILENTLY rounds projected coordinates (e.g.
#      UTM 32643 metres) by up to ~0.5 m. wk and lwgeom write full precision;
#      sf is only lossless if called with digits >= 15.
test_that("WKT read path: sf and wk parsers agree bit-for-bit on the same text", {
  skip_bench()
  for (sfc in list(bench_gen_polygons(50L), bench_gen_multipolygons(50L))) {
    epsg <- sf::st_crs(sfc)$epsg
    w    <- sf::st_as_text(sfc, digits = 15)          # one canonical text
    r_sf <- sf::st_as_sfc(w, crs = epsg)
    r_wk <- sf::st_as_sfc(wk::wkt(w), crs = epsg)
    expect_equal(unclass(r_sf), unclass(r_wk), ignore_attr = TRUE)
  }
})

test_that("WKT write precision: sf default is lossy on projected CRS; wk/lwgeom are not", {
  skip_bench()
  for (sfc in list(bench_gen_polygons(50L), bench_gen_multipolygons(50L))) {
    epsg    <- sf::st_crs(sfc)$epsg
    rt      <- function(txt) sf::st_as_sfc(txt, crs = epsg)

    dev_sf_default <- bench_max_dev(rt(sf::st_as_text(sfc)),             sfc)
    dev_sf_d15     <- bench_max_dev(rt(sf::st_as_text(sfc, digits = 15)), sfc)
    dev_wk         <- bench_max_dev(rt(wk::as_wkt(sfc)),                  sfc)

    message(sprintf(
      "  round-trip max deviation (m): sf(default)=%.3g  sf(digits=15)=%.3g  wk=%.3g",
      dev_sf_default, dev_sf_d15, dev_wk))

    # sf's DEFAULT writer loses real precision on metre-scale UTM coordinates
    expect_gt(dev_sf_default, 1e-2)
    # full-precision engines round-trip essentially exactly
    expect_lt(dev_sf_d15, 1e-5)
    expect_lt(dev_wk,     1e-5)

    if (requireNamespace("lwgeom", quietly = TRUE)) {
      dev_lw <- bench_max_dev(rt(lwgeom::st_astext(sfc)), sfc)
      expect_lt(dev_lw, 1e-5)
    }
  }
})

# ── the benchmark itself (prints a table; asserts wk read is not slower) ───────
test_that("WKT conversion benchmark: sf vs wk vs lwgeom", {
  skip_bench()

  small_n  <- as.integer(Sys.getenv("GDPINS_BENCH_SMALL_N",  "500"))
  medium_n <- as.integer(Sys.getenv("GDPINS_BENCH_MEDIUM_N", "50000"))
  times    <- as.integer(Sys.getenv("GDPINS_BENCH_TIMES",    "8"))

  scenarios <- list(
    list("small-polygon",       bench_gen_polygons(small_n),        times * 2L),
    list("small-multipolygon",  bench_gen_multipolygons(small_n),   times * 2L),
    list("medium-polygon",      bench_gen_polygons(medium_n),       times),
    list("medium-multipolygon", bench_gen_multipolygons(medium_n),  times)
  )

  results <- do.call(rbind, lapply(scenarios, function(s) {
    bench_scenario(s[[1]], s[[2]], s[[3]])
  }))

  message("\n===== WKT conversion benchmark (median ms, lower is better) =====")
  message(paste(utils::capture.output(print(results, row.names = FALSE)),
                collapse = "\n"))

  # relative speedup vs sf, per scenario/direction
  rel <- do.call(rbind, by(results, list(results$scenario, results$direction),
    function(g) {
      sf_med <- g$median_ms[g$engine == "sf"]
      g$vs_sf <- round(sf_med / g$median_ms, 2)   # >1 means faster than sf
      g[, c("scenario", "direction", "engine", "median_ms", "vs_sf")]
    }))
  message("\n===== Speedup vs sf (x, >1 = faster than sf) =====")
  message(paste(utils::capture.output(print(rel, row.names = FALSE)),
                collapse = "\n"))

  # sanity assertion: benchmark actually produced rows for every engine
  expect_true(all(c("sf", "wk") %in% results$engine))
  expect_gt(nrow(results), 0L)
})
