# Test whether a local file can actually be opened for reading

[`file.exists()`](https://rdrr.io/r/base/files.html) and
[`file.access()`](https://rdrr.io/r/base/file.access.html) both consult
metadata only, so a file held open by another program (Word, Excel, a
running R session) still looks fine. Uploads hand libcurl a *path*, and
curl only opens it mid-request – at which point the failure surfaces as
an opaque `"read error getting mime data"`. Opening the file up front
turns that into an actionable, per-file error – but on Windows a
byte-range lock (as held by Microsoft Office) lets the open succeed
while [`readBin()`](https://rdrr.io/r/base/readBin.html) silently
returns 0 bytes, so a 1-byte read probe is needed to actually catch it.

## Usage

``` r
.file_is_readable(path)
```

## Arguments

- path:

  Character scalar. Path to a local file.

## Value

`TRUE` if the file could be opened and read from.
