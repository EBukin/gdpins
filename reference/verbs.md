# Read/write verbs for gdpins boards

Core verbs for writing R objects to a board and reading them back.
Writes fan out to all non-NULL board components (Drive, local). Reads
are local-first: local → Drive.
