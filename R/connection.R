rclinvarbitration_sql_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

rclinvarbitration_normalize_duckdb_version <- function(version) {
  version <- as.character(version)
  if (length(version) != 1L || is.na(version) ||
      !grepl("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", version)) {
    stop("DuckDB engine version must be an exact release such as 'v1.5.3'.", call. = FALSE)
  }
  if (startsWith(version, "v")) version else paste0("v", version)
}

rclinvarbitration_connection_version <- function(con) {
  version <- DBI::dbGetQuery(con, "SELECT version() AS version")$version
  if (length(version) != 1L || is.na(version)) {
    stop("could not determine the DuckDB engine version.", call. = FALSE)
  }
  rclinvarbitration_normalize_duckdb_version(version)
}

rclinvarbitration_normalize_duckdb_platform <- function(platform) {
  platform <- as.character(platform)
  if (length(platform) != 1L || is.na(platform) ||
      !grepl("^[A-Za-z0-9_]+$", platform)) {
    stop("DuckDB platform must be one exact platform identifier.", call. = FALSE)
  }
  platform
}

rclinvarbitration_connection_platform <- function(con) {
  platform <- DBI::dbGetQuery(con, "PRAGMA platform")$platform
  if (length(platform) != 1L || is.na(platform)) {
    stop("could not determine the DuckDB engine platform.", call. = FALSE)
  }
  rclinvarbitration_normalize_duckdb_platform(platform)
}

rclinvarbitration_installed_duckdb_platform <- function() {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("supply `duckdb_platform` or install the duckdb package.", call. = FALSE)
  }
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  rclinvarbitration_connection_platform(con)
}

rclinvarbitration_bundled_duckdb_versions <- function(root) {
  versions <- list.files(root, pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
  versions <- versions[vapply(versions, function(version) {
    length(list.files(
      file.path(root, version), pattern = "^rclinvarbitration\\.duckdb_extension$",
      recursive = TRUE
    )) > 0L
  }, logical(1))]
  if (!length(versions)) return(character())
  paste0("v", as.character(sort(numeric_version(sub("^v", "", versions)))))
}

#' Locate a version-matched RClinVarbitration DuckDB extension
#'
#' The package uses DuckDB's unstable C extension ABI for its streaming table
#' function, so it bundles one artifact per supported exact engine release.
#'
#' @param duckdb_version Exact DuckDB version, with or without a `v` prefix.
#'   `NULL` selects the version reported by the installed `duckdb` package.
#' @param duckdb_platform Exact platform reported by `PRAGMA platform`. `NULL`
#'   queries a temporary connection to the installed `duckdb` package. DuckDB
#'   distinguishes `windows_amd64` from R-devel's `windows_amd64_mingw` even
#'   though both artifacts contain the same MinGW-built machine code.
#' @return An absolute extension path.
#' @export
rclinvarbitration_extension_path <- function(
    duckdb_version = NULL, duckdb_platform = NULL) {
  if (is.null(duckdb_version)) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      stop("supply `duckdb_version` or install the duckdb package.", call. = FALSE)
    }
    namespace <- asNamespace("duckdb")
    getter <- get0("get_duckdb_version", envir = namespace, mode = "function", inherits = FALSE)
    version <- if (!is.null(getter)) getter() else get0("duckdb_version", envir = namespace, inherits = FALSE)
    if (is.null(version)) stop("could not determine the installed DuckDB version.", call. = FALSE)
    duckdb_version <- version
  }
  duckdb_version <- rclinvarbitration_normalize_duckdb_version(duckdb_version)
  if (is.null(duckdb_platform)) {
    duckdb_platform <- rclinvarbitration_installed_duckdb_platform()
  }
  duckdb_platform <- rclinvarbitration_normalize_duckdb_platform(duckdb_platform)
  root <- system.file("rclinvarbitration_extension", "build", package = "RClinVarbitration", mustWork = TRUE)
  path <- file.path(
    root, duckdb_version, duckdb_platform, "rclinvarbitration.duckdb_extension"
  )
  if (!file.exists(path)) {
    bundled <- rclinvarbitration_bundled_duckdb_versions(root)
    platform_root <- file.path(root, duckdb_version)
    platforms <- if (dir.exists(platform_root)) {
      list.dirs(platform_root, recursive = FALSE, full.names = FALSE)
    } else {
      character()
    }
    stop(
      "RClinVarbitration has no artifact for DuckDB ", duckdb_version,
      " on ", duckdb_platform, ". Bundled versions: ",
      if (length(bundled)) paste(bundled, collapse = ", ") else "none",
      "; platforms for this version: ",
      if (length(platforms)) paste(platforms, collapse = ", ") else "none",
      ". Install a release that supports this exact engine version and platform.",
      call. = FALSE
    )
  }
  normalizePath(path, mustWork = TRUE)
}

#' Enable native ClinVar and PubMed XML scanning on a DuckDB connection
#'
#' Loads the package-owned `rclinvarbitration` extension. Its native
#' `clinvar_xml_entities(path)` and `rclinvarbitration_pubmed_xml_rows(path)`
#' table functions are concrete one-pass staging surfaces for
#' [rclinvarbitration_import_xml()] and
#' `rclinvarbitration_import_pubmed()`. `rclinvar_json_field()` remains the
#' compact ClinVar field scalar. The
#' connection must have been created with
#' `duckdb::duckdb(config = list(allow_unsigned_extensions = "true"))`, as for
#' any locally built DuckDB extension.
#'
#' @param con A DuckDB DBI connection.
#' @param extension_path Optional explicit exact-version extension path.
#' @return `con`, invisibly.
#' @export
rclinvarbitration_enable <- function(con, extension_path = NULL) {
  version <- rclinvarbitration_connection_version(con)
  platform <- rclinvarbitration_connection_platform(con)
  if (is.null(extension_path)) {
    extension_path <- rclinvarbitration_extension_path(version, platform)
  }
  if (!is.character(extension_path) || length(extension_path) != 1L ||
      is.na(extension_path) || !nzchar(extension_path)) {
    stop("`extension_path` must be NULL or a non-empty character scalar.", call. = FALSE)
  }
  extension_path <- normalizePath(extension_path, mustWork = TRUE)
  DBI::dbExecute(con, paste("LOAD", rclinvarbitration_sql_string(extension_path)))
  invisible(con)
}
