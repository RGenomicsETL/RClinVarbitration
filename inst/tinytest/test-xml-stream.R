fixture <- system.file("extdata", "VCV_XML_VCV000091629.xml.gz", package = "RClinVarbitration")
expect_true(nzchar(fixture))
expect_true(file.exists(fixture))

supported_versions <- paste0("v1.5.", 0:4)
platform_con <- DBI::dbConnect(duckdb::duckdb())
engine_platform <- DBI::dbGetQuery(platform_con, "PRAGMA platform")$platform
DBI::dbDisconnect(platform_con, shutdown = TRUE)
artifact_paths <- vapply(
  supported_versions,
  rclinvarbitration_extension_path,
  character(1),
  duckdb_platform = engine_platform
)
expect_equal(basename(dirname(dirname(artifact_paths))), supported_versions)
expect_equal(basename(dirname(artifact_paths)), rep(engine_platform, length(supported_versions)))
expect_true(all(file.exists(artifact_paths)))
expect_error(
  rclinvarbitration_extension_path("v1.4.3", engine_platform), "no artifact"
)

extension_directory <- tempfile("rclinvarbitration-duckdb-extensions-")
con <- DBI::dbConnect(duckdb::duckdb(config = list(
  allow_unsigned_extensions = "true",
  extension_directory = extension_directory
)))
rclinvarbitration_enable(con)
json_extension <- DBI::dbGetQuery(con, paste(
  "SELECT installed FROM duckdb_extensions() WHERE extension_name = 'json'"
))
expect_false(json_extension$installed)
escaped_json <- '{"value":"line\\nquote\\"slash\\\\"}'
escaped_field <- DBI::dbGetQuery(con, paste0(
  "SELECT rclinvar_json_field(", DBI::dbQuoteString(con, escaped_json), ", 'value') AS value"
))$value
expect_equal(escaped_field, "line\nquote\"slash\\")
fixture_sql <- as.character(DBI::dbQuoteString(con, fixture))

entities <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM clinvar_xml_entities(", fixture_sql, ") ORDER BY entity_ordinal"
))
expect_true(nrow(entities) > 50L)
expect_true(nrow(entities) < 500L)
expect_false(any(grepl("clinvar:xml", entities$entity_id, fixed = TRUE)))
expect_equal(unique(entities$vcv_accession), "VCV000091629")
expect_equal(sum(entities$entity_type == "variation"), 1L)
expect_equal(sum(entities$entity_type == "rcv_assertion"), 4L)
expect_equal(sum(entities$entity_type == "scv_assertion"), 6L)
expect_true(all(grepl("^\\{.*\\}$", entities$fields_json)))

selected_fields <- DBI::dbGetQuery(con, paste0(
  "SELECT entity_type, rclinvar_json_field(fields_json, 'classification') AS classification, ",
  "rclinvar_json_field(fields_json, 'value') AS value ",
  "FROM clinvar_xml_entities(", fixture_sql, ")"
))
expect_true(any(selected_fields$entity_type == "scv_assertion" & selected_fields$classification == "Pathogenic", na.rm = TRUE))
expect_true(any(selected_fields$entity_type == "text" & grepl("splice", selected_fields$value, ignore.case = TRUE), na.rm = TRUE))
expect_false(any(grepl("^CREATE INDEX", rclinvarbitration_schema_sql())))

# Rows from a process terminated before writing its completion marker are
# removed before a fresh import of the same release identifier.
rclinvarbitration_init(con)
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants (release_id, record_ordinal, vcv_accession)
  VALUES ('fixture-vcv', 999, 'STALE')
")
fixture_download <- structure(
  fixture,
  download = data.frame(
    url = "https://example.test/fixture.xml.gz",
    md5 = "0123456789abcdef0123456789abcdef"
  )
)
counts <- rclinvarbitration_import_xml(
  con, fixture_download, release_id = "fixture-vcv"
)
release <- DBI::dbGetQuery(con, "SELECT * FROM clinvar_releases")
expect_equal(release$source_url, "https://example.test/fixture.xml.gz")
expect_equal(release$source_md5, "0123456789abcdef0123456789abcdef")
expect_equal(release$source_bytes, file.info(fixture)$size)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_variants WHERE vcv_accession = 'STALE'")$n, 0)
expect_equal(counts[["variants"]], 1)
expect_equal(counts[["alleles"]], 1)
expect_equal(counts[["rcv_assertions"]], 4)
expect_equal(counts[["scv_assertions"]], 6)
expect_equal(counts[["observations"]], 6)
expect_true(counts[["conditions"]] >= 10)
expect_true(counts[["citations"]] > 10)
expect_true(counts[["text"]] > 10)
expect_false("clinvar_statements" %in% DBI::dbListTables(con))

variant <- DBI::dbGetQuery(con, "
  SELECT vcv_accession, vcv_version, variation_id, variation_name,
         aggregate_classification, aggregate_review_status
  FROM clinvar_variants
")
expect_equal(variant$vcv_accession, "VCV000091629")
expect_equal(variant$vcv_version, 19L)
expect_equal(variant$variation_id, 91629)
expect_equal(variant$aggregate_classification, "Pathogenic/Likely pathogenic")
expect_equal(variant$aggregate_review_status, "criteria provided, multiple submitters, no conflicts")

alleles <- DBI::dbGetQuery(con, "
  SELECT allele_id, variation_id, canonical_spdi
  FROM clinvar_alleles
")
expect_equal(alleles$allele_id, 97106)
expect_equal(alleles$variation_id, 91629)
expect_equal(alleles$canonical_spdi, "NC_000017.11:43082401:A:C")

locations <- DBI::dbGetQuery(con, "
  SELECT assembly, chromosome, position_vcf, reference, alternate
  FROM clinvar_normalized_alleles ORDER BY assembly
")
expect_equal(locations$assembly, c("GRCh37", "GRCh38"))
expect_equal(locations$chromosome, c("17", "17"))
expect_equal(locations$position_vcf, c(41234419, 43082402))
expect_equal(locations$reference, c("A", "A"))
expect_equal(locations$alternate, c("C", "C"))

scvs <- DBI::dbGetQuery(con, "
  SELECT scv_accession, submitter_name, classification, review_status
  FROM clinvar_scv_assertions ORDER BY scv_accession
")
expect_equal(nrow(scvs), 6L)
expect_true("SCV003995313" %in% scvs$scv_accession)
expect_true(all(scvs$classification %in% c("Pathogenic", "Likely pathogenic")))
expect_true(any(scvs$submitter_name == "Ambry Genetics"))

disease_aggregates <- DBI::dbGetQuery(con, "
  SELECT rcv_accession, disease_database, disease_identifier,
         disease_name, aggregate_classification
  FROM clinvar_disease_aggregates ORDER BY rcv_accession
")
expect_equal(nrow(disease_aggregates), 4L)
expect_equal(disease_aggregates$disease_database, rep("MedGen", 4L))
expect_equal(
  disease_aggregates$disease_identifier,
  c("C2676676", "C3661900", "C0027672", "C0677776")
)
expect_true(all(nzchar(disease_aggregates$disease_name)))
expect_true(all(nzchar(disease_aggregates$aggregate_classification)))

disease_submissions <- DBI::dbGetQuery(con, "
  SELECT scv_accession, disease_database, disease_identifier, disease_key, classification
  FROM clinvar_disease_submissions ORDER BY scv_accession
")
expect_equal(nrow(disease_submissions), 6L)
expect_equal(length(unique(disease_submissions$scv_accession)), 6L)
expect_true(any(disease_submissions$disease_identifier == "C0027672", na.rm = TRUE))
expect_true(all(nzchar(disease_submissions$disease_key)))

policy <- DBI::dbGetQuery(con, "
  SELECT policy_version, profile_id, disease_key, policy_classification, gold_stars
  FROM clinvar_policy_decisions ORDER BY disease_key
")
expect_equal(nrow(policy), 5L)
expect_equal(unique(policy$policy_version), rclinvarbitration_policy_version())
expect_equal(unique(policy$profile_id), "default")
expect_true(all(policy$policy_classification == "Pathogenic/Likely Pathogenic"))
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_pathogenic_alleles")$n,
  10
)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_allele_decisions")$n,
  1
)
gene_summary <- DBI::dbGetQuery(con, "SELECT * FROM clinvar_gene_summaries")
expect_equal(nrow(gene_summary), 1L)
expect_equal(gene_summary$symbol, "BRCA1")
expect_equal(gene_summary$gene_id, 672)
expect_equal(gene_summary$disease_decision_count, 5)
expect_equal(gene_summary$pathogenic_disease_decision_count, 5)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_semantic_documents")$n,
  counts[["text"]]
)
literature <- DBI::dbGetQuery(con, "
  SELECT source, identifier, literature_url FROM clinvar_literature_links
  WHERE lower(source) = 'pubmed'
")
expect_true(nrow(literature) > 5L)
expect_true(all(grepl("^https://pubmed.ncbi.nlm.nih.gov/", literature$literature_url)))
# Curated against the source XML: PMID 21735045 is attached to
# SCV000827729 (assertion 1599586), not to the VCV as an admissibility claim.
curated_literature <- DBI::dbGetQuery(con, "
  SELECT l.context_type, l.context_id, l.scv_entity_id, s.scv_accession,
         l.source, l.identifier, l.literature_url
  FROM clinvar_literature_links l
  JOIN clinvar_scv_assertions s
    ON s.release_id = l.release_id AND s.assertion_entity_id = l.scv_entity_id
  WHERE l.identifier = '21735045'
")
expect_equal(nrow(curated_literature), 1L)
expect_equal(curated_literature$context_type, "scv_assertion")
expect_equal(curated_literature$context_id, "VCV000091629#assertion/1599586")
expect_equal(curated_literature$scv_accession, "SCV000827729")
expect_equal(curated_literature$source, "PubMed")
expect_equal(
  curated_literature$literature_url,
  "https://pubmed.ncbi.nlm.nih.gov/21735045/"
)

# A curated real NCBI record from the measured 2026-07-02 release validates
# HPO projection while preserving source context. This asserts the link only,
# never its clinical relevance or evidence admissibility.
curated_fixture <- system.file(
  "extdata", "VCV_XML_HPO_CURATED_VCV000158424.xml.gz",
  package = "RClinVarbitration"
)
rclinvarbitration_import_xml(con, curated_fixture, "curated-hpo-projection")
curated_hpo <- DBI::dbGetQuery(con, "
  SELECT h.vcv_accession, h.scv_entity_id, s.scv_accession, h.context_type,
         h.context_id, h.hpo_id, h.xref_type
  FROM clinvar_hpo_terms h
  JOIN clinvar_scv_assertions s
    ON s.release_id = h.release_id AND s.assertion_entity_id = h.scv_entity_id
  WHERE h.release_id = 'curated-hpo-projection'
")
expect_equal(nrow(curated_hpo), 1L)
expect_equal(curated_hpo$vcv_accession, "VCV000158424")
expect_equal(curated_hpo$scv_entity_id, "VCV000158424#assertion/340778")
expect_equal(curated_hpo$scv_accession, "SCV000192942")
expect_equal(curated_hpo$context_type, "condition")
expect_equal(
  curated_hpo$context_id,
  "VCV000158424#assertion/340778#condition/2"
)
expect_equal(curated_hpo$hpo_id, "HP:0002282")
expect_true(is.na(curated_hpo$xref_type))
parquet <- tempfile("clinvar-decisions-", fileext = ".parquet")
exported <- rclinvarbitration_export_clinvarbitration_parquet(
  con, parquet, release_id = "fixture-vcv", assembly = "GRCh38"
)
expect_equal(exported$rows, 1)
expect_equal(
  DBI::dbGetQuery(con, paste0("SELECT * FROM read_parquet(", DBI::dbQuoteString(con, parquet), ")")),
  data.frame(
    contig = "chr17", position = 43082402L, reference = "A", alternate = "C",
    clinical_significance = "Pathogenic/Likely Pathogenic", gold_stars = 1L,
    allele_id = 97106L
  )
)
expect_error(
  rclinvarbitration_export_clinvarbitration_parquet(con, parquet, "fixture-vcv"),
  "already exists"
)
unlink(parquet)

enhanced_parquet <- tempfile(
  "clinvar-decisions-enhanced-", fileext = ".parquet"
)
enhanced_export <- rclinvarbitration_export_clinvarbitration_parquet(
  con, enhanced_parquet, release_id = "fixture-vcv", assembly = "GRCh38",
  schema = "enhanced"
)
expect_equal(enhanced_export$schema, "enhanced")
expect_equal(enhanced_export$release_receipt$release_id, "fixture-vcv")
enhanced <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT record_key, vcv_accession, disease_key, clinical_significance, ",
    "content_sha256, ",
    "list_count(scv_submissions) AS scv_count, ",
    "list_count(rcv_aggregates) AS rcv_count, ",
    "list_count(genes) AS gene_count FROM read_parquet(",
    DBI::dbQuoteString(con, enhanced_parquet), ")"
  )
)
expect_equal(nrow(enhanced), enhanced_export$rows)
expect_true(all(nzchar(enhanced$record_key)))
expect_true(all(nchar(enhanced$content_sha256) == 64L))
expect_true(all(enhanced$vcv_accession == "VCV000091629"))
expect_true(all(enhanced$scv_count >= 1L))
expect_true(all(enhanced$rcv_count == 4L))
expect_true(all(enhanced$gene_count >= 1L))
expect_error(
  rclinvarbitration_export_clinvarbitration_parquet(
    con, tempfile(fileext = ".parquet"), "fixture-vcv",
    schema = "enhanced", submitter_exclusions = "Example laboratory"
  ),
  "requires a named policy profile"
)
unlink(enhanced_parquet)

blinded_parquet <- tempfile("clinvar-decisions-blinded-", fileext = ".parquet")
submitters <- unique(scvs$submitter_name)
policy_version_sql <- DBI::dbQuoteString(con, rclinvarbitration_policy_version())
DBI::dbExecute(con, paste0(
  "INSERT INTO clinvar_policy_profiles VALUES (", policy_version_sql,
  ", 'combined-exclusions', 'test profile')"
))
DBI::dbExecute(con, paste0(
  "INSERT INTO clinvar_policy_submitter_exclusions VALUES (", policy_version_sql,
  ", 'combined-exclusions', ", DBI::dbQuoteString(con, submitters[[1L]]),
  ", NULL, 'stored exclusion')"
))
profile_count <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_profiles")$n
exclusion_count <- DBI::dbGetQuery(
  con, "SELECT count(*) AS n FROM clinvar_policy_submitter_exclusions"
)$n
blinded_export <- rclinvarbitration_export_clinvarbitration_parquet(
  con, blinded_parquet, release_id = "fixture-vcv", assembly = "GRCh38",
  profile_id = "combined-exclusions", submitter_exclusions = submitters[-1L]
)
expect_equal(blinded_export$rows, 0)
expect_equal(
  sort(blinded_export$submitter_exclusions),
  sort(unique(tolower(submitters[-1L])))
)
expect_equal(
  DBI::dbGetQuery(con, paste0(
    "SELECT count(*) AS n FROM read_parquet(",
    DBI::dbQuoteString(con, blinded_parquet), ")"
  ))$n,
  0
)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_profiles")$n, profile_count)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_submitter_exclusions")$n,
  exclusion_count
)
unlink(blinded_parquet)

write_gzip_lines <- function(path, lines) {
  output <- gzfile(path, "wt")
  on.exit(close(output), add = TRUE)
  writeLines(lines, output)
}
submission_summary <- tempfile("submission-summary-", fileext = ".txt.gz")
variant_summary <- tempfile("variant-summary-", fileext = ".txt.gz")
reproduced <- tempfile("reproduced-decisions-", fileext = ".parquet")
tsv <- function(...) paste(c(...), collapse = intToUtf8(9L))
write_gzip_lines(variant_summary, c(
  tsv("#AlleleID", "Assembly", "Chromosome", "VariationID", "PositionVCF", "ReferenceAlleleVCF", "AlternateAlleleVCF"),
  tsv("11", "GRCh38", "1", "1", "101", "A", "G"),
  tsv("12", "GRCh38", "2", "2", "202", "C", "T"),
  tsv("13", "GRCh38", "X", "3", "303", "G", "A")
))
write_gzip_lines(submission_summary, c(
  rep("## ClinVar submission summary metadata", 18L),
  tsv("#VariationID", "ClinicalSignificance", "DateLastEvaluated", "ReviewStatus", "Submitter"),
  tsv("1", "Pathogenic", "Jan 01, 2010", "no assertion criteria provided", "old-lab"),
  tsv("1", "Benign", "Jan 01, 2020", "criteria provided, single submitter", "new-lab"),
  tsv("2", "Pathogenic", "Jan 01, 2020", "reviewed by expert panel", "expert-first"),
  tsv("2", "Benign", "Jan 02, 2020", "practice guideline", "practice-second"),
  tsv("3", "Pathogenic", "Jan 01, 2020", "criteria provided, single submitter", "blind-lab"),
  tsv("3", "Benign", "Jan 01, 2020", "criteria provided, single submitter", "independent-lab")
))
reproduced_info <- rclinvarbitration_reproduce_clinvarbitration_parquet(
  con, submission_summary, variant_summary, reproduced,
  submitter_exclusions = "blind-lab"
)
expect_equal(reproduced_info$rows, 3)
reproduced_rows <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM read_parquet(", DBI::dbQuoteString(con, reproduced), ") ORDER BY allele_id"
))
expect_equal(reproduced_rows$contig, c("chr1", "chr2", "chrX"))
expect_equal(reproduced_rows$clinical_significance, c(
  "Benign", "Pathogenic/Likely Pathogenic", "Benign"
))
expect_equal(reproduced_rows$gold_stars, c(1L, 4L, 1L))
unlink(c(submission_summary, variant_summary, reproduced))

text <- DBI::dbGetQuery(con, "
  SELECT s.scv_accession, t.section, t.text
  FROM clinvar_text t
  LEFT JOIN clinvar_scv_assertions s
    ON s.release_id = t.release_id AND s.assertion_entity_id = t.scv_entity_id
")
expect_true(any(text$scv_accession == "SCV003995313" & grepl("splice", text$text, ignore.case = TRUE)))
expect_true(any(grepl("condition_name", text$section, fixed = TRUE)))
expect_true(all(text$text == trimws(text$text)))

expect_error(
  rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv", source_md5 = "bad"),
  "32-character"
)
expect_error(rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv"), "already exists")
replaced <- rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv", replace = TRUE)
expect_equal(replaced[["variants"]], 1)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_releases")$n, 2)

DBI::dbDisconnect(con, shutdown = TRUE)
