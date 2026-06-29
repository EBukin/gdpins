# Save a ggplot figure to disk

Renders a ggplot object to a PNG or SVG file in `dir`. The ggplot object
itself is never stored in a pin. File name is `<name>.<device>`.

## Usage

``` r
gdpins_save_figure(
  plot,
  name,
  dir,
  width = 7,
  height = 5,
  dpi = 300,
  device = c("png", "svg")
)
```

## Arguments

- plot:

  A `ggplot` object.

- name:

  Character scalar. Base file name (without extension).

- dir:

  Character scalar. Output directory path.

- width:

  Numeric scalar. Figure width in inches. Default `7`.

- height:

  Numeric scalar. Figure height in inches. Default `5`.

- dpi:

  Integer scalar. Resolution in DPI. Default `300`.

- device:

  Character scalar. One of `c("png", "svg")`. Default `"png"`.

## Value

Invisibly, the path to the saved file.
