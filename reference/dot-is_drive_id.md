# Detect whether a string looks like a Drive folder ID

Heuristic: no `"/"` and no spaces -\> Drive ID; otherwise -\> path
string.

## Usage

``` r
.is_drive_id(x)
```

## Arguments

- x:

  Character scalar.

## Value

Logical scalar.
