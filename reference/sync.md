# Synchronisation engine

User-invokable sync between Drive and local. Never automatic – the user
decides when to synchronise. Conflict resolution:

- Versioned boards: both writes become versions (no loss).

- Raw / unversioned: interactive prompt or stop + report.
