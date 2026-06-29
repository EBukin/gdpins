# Read/write verbs for gdpins boards

Core verbs for writing R objects to a board and reading them back.
Writes fan out to all non-NULL board components (Drive, cache, local).
Reads are local-first: local → cache → Drive.
