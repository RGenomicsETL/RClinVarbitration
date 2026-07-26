# Native dependency boundary

The native extension is intentionally small:

- DuckDB C extension headers are pinned for every bundled exact engine release
  under `duckdb_capi/v1.5.0/` through `v1.5.5/`. Each
  `duckdb_headers.json` records its upstream revision and repaired-header
  checksums; `versions.txt` is the build manifest.
- `tools/fetch_duckdb_headers.R --ref vMAJOR.MINOR.PATCH` is the explicit
  vendoring tool. It may download or use an explicit local DuckDB checkout, but
  `configure` never accesses the network.
- libxml2 is presently a host dependency discovered by `pkg-config`. The
  extension does not call libxml2 outside `rclinvarbitration_extension.c`.
- The package builds one artifact per exact DuckDB engine version and records
  `C_STRUCT_UNSTABLE` metadata. It must never load a nearby-version artifact.

A future platform expansion must either vendor a pinned static libxml2 build
with hidden symbols or add a documented platform adapter. It must not replace
the streaming parser with an R XML DOM or a community-extension runtime load.
