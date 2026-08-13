# Decisions

Approaches tried and rejected, with why. This is what stops a future session from re-proposing a design that already failed here.

Add one entry per rejected approach: what was tried, why it was rejected, and what to do instead.

<!-- Example:
## Queueing analysis jobs per-row
Tried: dispatching one job per screener row for parallelism.
Rejected: queue overhead dominated at typical batch sizes (10-50 rows); serial processing in one job was faster and simpler.
Instead: batch rows into a single job, chunked at 50.
-->
