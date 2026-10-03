# Resolve the parquet (de)serialisation engine

Resolve the parquet (de)serialisation engine

## Usage

``` r
.gdpins_parquet_engine(engine = NULL)
```

## Arguments

- engine:

  Character scalar `"arrow"` or `"nanoparquet"`, or `NULL` to fall back
  to the `gdpins.parquet_engine` option (default `"arrow"`).

## Value

`"arrow"` or `"nanoparquet"`.
