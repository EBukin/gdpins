# Drive adapter — thin seam over googledrive

All `googledrive`-specific operations are isolated behind this adapter
so tests can inject a fake. Every Drive-touching function in the package
takes the adapter from the board or connection object and calls the
wrappers below — **never** `googledrive::*` directly outside this file.

S3 class `gdpins_drive_adapter`: a named list of closures plus `kind`
(`"real"` \| `"fake"`). Paths are **relative to the adapter's drive
root**, "/"-separated (e.g.
`"kazLandEconImpact-data/data-raw/parcels.parquet"`).
