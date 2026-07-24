rclinvarbitration_download_spec <- function(release, file, base_url) {
  latest <- identical(release, "latest")
  archive_suffix <- if (latest) "" else paste0("_", release)
  switch(
    file,
    vcv_xml = {
      filename <- if (latest) {
        "ClinVarVCVRelease_00-latest.xml.gz"
      } else {
        paste0("ClinVarVCVRelease_", release, ".xml.gz")
      }
      year <- if (latest) NA_integer_ else as.integer(substr(release, 1L, 4L))
      directory <- if (latest || year >= 2025L) {
        "xml"
      } else {
        paste0("xml/archive/", year)
      }
      relative_url <- paste(directory, filename, sep = "/")
      list(filename = filename, url = paste(base_url, relative_url, sep = "/"), checksum = TRUE)
    },
    submission_summary = {
      filename <- paste0("submission_summary", archive_suffix, ".txt.gz")
      directory <- if (latest) "tab_delimited" else "tab_delimited/archive"
      list(
        filename = filename,
        url = paste(base_url, directory, filename, sep = "/"),
        checksum = latest
      )
    },
    variant_summary = {
      filename <- paste0("variant_summary", archive_suffix, ".txt.gz")
      directory <- if (latest) "tab_delimited" else "tab_delimited/archive"
      list(
        filename = filename,
        url = paste(base_url, directory, filename, sep = "/"),
        checksum = latest
      )
    }
  )
}

rclinvarbitration_download_one <- function(spec, cache_dir, overwrite, quiet) {
  destination <- file.path(cache_dir, spec$filename)
  expected_md5 <- NULL
  checksum_temp <- NULL
  if (isTRUE(spec$checksum)) {
    checksum_temp <- tempfile(pattern = "clinvar-md5-", tmpdir = cache_dir)
    on.exit(unlink(checksum_temp), add = TRUE)
    status <- utils::download.file(
      paste0(spec$url, ".md5"), checksum_temp,
      mode = "wb", quiet = quiet
    )
    if (!identical(status, 0L)) {
      stop("Failed to download NCBI checksum for `", spec$filename, "`.", call. = FALSE)
    }
    checksum_text <- paste(readLines(checksum_temp, warn = FALSE), collapse = " ")
    match <- regexpr("[[:xdigit:]]{32}", checksum_text)
    if (match[[1L]] < 0L) {
      stop("NCBI returned an invalid MD5 sidecar for `", spec$filename, "`.", call. = FALSE)
    }
    expected_md5 <- tolower(regmatches(checksum_text, match))
  }

  cache_hit <- file.exists(destination) && !overwrite
  if (cache_hit && !is.null(expected_md5)) {
    cache_hit <- identical(tolower(unname(tools::md5sum(destination))), expected_md5)
  }
  if (!cache_hit) {
    temporary <- tempfile(pattern = paste0(spec$filename, ".part-"), tmpdir = cache_dir)
    on.exit(unlink(temporary), add = TRUE)
    status <- utils::download.file(spec$url, temporary, mode = "wb", quiet = quiet)
    if (!identical(status, 0L)) {
      stop("Failed to download NCBI file `", spec$filename, "`.", call. = FALSE)
    }
    if (!is.null(expected_md5)) {
      actual_md5 <- tolower(unname(tools::md5sum(temporary)))
      if (!identical(actual_md5, expected_md5)) {
        stop(
          "MD5 mismatch for `", spec$filename, "`: expected ", expected_md5,
          ", received ", actual_md5, ".",
          call. = FALSE
        )
      }
    }
    if (file.exists(destination) && unlink(destination) != 0L) {
      stop("Could not replace cached file `", destination, "`.", call. = FALSE)
    }
    if (!file.rename(temporary, destination)) {
      stop("Could not move the completed download to `", destination, "`.", call. = FALSE)
    }
  }

  list(
    path = normalizePath(destination, mustWork = TRUE),
    url = spec$url,
    md5 = if (is.null(expected_md5)) NA_character_ else expected_md5,
    cache_hit = cache_hit
  )
}

#' Download official ClinVar source files
#'
#' Downloads either the current ClinVar release or a named monthly archive from
#' the NCBI HTTPS service. The flat reports are the compact default input to
#' [rclinvarbitration_import_flat()]. VCV XML feeds the same scalar `clinvar`
#' table when an analysis also needs observations, citations, conditions,
#' attributes, or attributable text that the flat reports do not contain.
#'
#' Existing files form a local cache. Current files and archived VCV XML files
#' are checked against NCBI's MD5 sidecar; a matching file is reused and a stale
#' or corrupt file is replaced only after a temporary download is verified.
#' NCBI does not publish MD5 sidecars
#' beside archived flat files, so those files are reused by name unless
#' `overwrite = TRUE`.
#'
#' A complete VCV release is several gigabytes. The default cache location is
#' returned by `tools::R_user_dir("RClinVarbitration", "cache")`. The function
#' raises R's download timeout to at least the value of option
#' `RClinVarbitration.download_timeout` (7200 seconds by default) for the call.
#'
#' @param release `"latest"` or a monthly archive in `"YYYY-MM"` form.
#' @param file One or more of `"vcv_xml"`, `"submission_summary"`, and
#'   `"variant_summary"`.
#' @param cache_dir Directory in which downloaded files are cached.
#' @param overwrite Download even when a valid cached file is present?
#' @param quiet Passed to [utils::download.file()].
#' @return A named character vector of local paths. The `download` attribute is
#'   a data frame containing source URLs, MD5 values when available, and cache
#'   hit status.
#' @examplesIf interactive()
#' xml <- rclinvarbitration_download_clinvar(release = "latest")
#' xml_2026_03 <- rclinvarbitration_download_clinvar(release = "2026-03")
#' @export
rclinvarbitration_download_clinvar <- function(
    release = "latest", file = "vcv_xml",
    cache_dir = tools::R_user_dir("RClinVarbitration", "cache"),
    overwrite = FALSE, quiet = FALSE) {
  if (!is.character(release) || length(release) != 1L || is.na(release) ||
      !(identical(release, "latest") || grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", release))) {
    stop("`release` must be \"latest\" or a monthly archive in \"YYYY-MM\" form.", call. = FALSE)
  }
  allowed_files <- c("vcv_xml", "submission_summary", "variant_summary")
  if (!is.character(file) || !length(file) || anyNA(file) ||
      any(!file %in% allowed_files) || anyDuplicated(file)) {
    stop(
      "`file` must contain unique values from: ",
      paste(allowed_files, collapse = ", "), ".",
      call. = FALSE
    )
  }
  if (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir) || !nzchar(cache_dir)) {
    stop("`cache_dir` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite) ||
      !is.logical(quiet) || length(quiet) != 1L || is.na(quiet)) {
    stop("`overwrite` and `quiet` must each be TRUE or FALSE.", call. = FALSE)
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(cache_dir)) {
    stop("Could not create `cache_dir`: ", cache_dir, call. = FALSE)
  }
  cache_dir <- normalizePath(cache_dir, mustWork = TRUE)
  configured_timeout <- getOption("RClinVarbitration.download_timeout", 7200)
  if (!is.numeric(configured_timeout) || length(configured_timeout) != 1L ||
      is.na(configured_timeout) || configured_timeout <= 0) {
    stop("Option `RClinVarbitration.download_timeout` must be a positive number.", call. = FALSE)
  }
  old_timeout <- options(timeout = max(getOption("timeout", 60), configured_timeout))
  on.exit(options(old_timeout), add = TRUE)
  base_url <- sub(
    "/+$", "",
    getOption(
      "RClinVarbitration.ncbi_base_url",
      "https://ftp.ncbi.nlm.nih.gov/pub/clinvar"
    )
  )

  details <- lapply(file, function(one_file) {
    spec <- rclinvarbitration_download_spec(release, one_file, base_url)
    rclinvarbitration_download_one(spec, cache_dir, overwrite, quiet)
  })
  paths <- stats::setNames(vapply(details, `[[`, character(1), "path"), file)
  attr(paths, "download") <- data.frame(
    file = file,
    release = release,
    path = unname(paths),
    url = vapply(details, `[[`, character(1), "url"),
    md5 = vapply(details, `[[`, character(1), "md5"),
    cache_hit = vapply(details, `[[`, logical(1), "cache_hit"),
    stringsAsFactors = FALSE
  )
  paths
}
