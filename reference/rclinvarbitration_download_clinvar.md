# Download official ClinVar source files

Downloads either the current ClinVar release or a named monthly archive
from the NCBI HTTPS service. The flat reports are the compact default
input to
[`rclinvarbitration_import_flat()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_flat.md).
VCV XML feeds the same scalar `clinvar` table when an analysis also
needs observations, citations, conditions, attributes, or attributable
text that the flat reports do not contain.

## Usage

``` r
rclinvarbitration_download_clinvar(
  release = "latest",
  file = "vcv_xml",
  cache_dir = tools::R_user_dir("RClinVarbitration", "cache"),
  overwrite = FALSE,
  quiet = FALSE
)
```

## Arguments

- release:

  `"latest"` or a monthly archive in `"YYYY-MM"` form.

- file:

  One or more of `"vcv_xml"`, `"submission_summary"`, and
  `"variant_summary"`.

- cache_dir:

  Directory in which downloaded files are cached.

- overwrite:

  Download even when a valid cached file is present?

- quiet:

  Passed to
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html).

## Value

A named character vector of local paths. The `download` attribute is a
data frame containing source URLs, MD5 values when available, and cache
hit status.

## Details

Existing files form a local cache. Current files and archived VCV XML
files are checked against NCBI's MD5 sidecar; a matching file is reused
and a stale or corrupt file is replaced only after a temporary download
is verified. NCBI does not publish MD5 sidecars beside archived flat
files, so those files are reused by name unless `overwrite = TRUE`.

A complete VCV release is several gigabytes. The default cache location
is returned by `tools::R_user_dir("RClinVarbitration", "cache")`. The
function raises R's download timeout to at least the value of option
`RClinVarbitration.download_timeout` (7200 seconds by default) for the
call.

## Examples

``` r
if (FALSE) { # interactive()
xml <- rclinvarbitration_download_clinvar(release = "latest")
xml_2026_03 <- rclinvarbitration_download_clinvar(release = "2026-03")
}
```
