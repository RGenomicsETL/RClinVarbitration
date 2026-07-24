con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)

# The public condition identity remains stable when only a package-generated
# condition key and preferred label change between releases.
DBI::dbAppendTable(con, "clinvar", data.frame(
  release_id = rep(c("release-old", "release-new"), each = 5L),
  record_kind = rep(
    c("variation", "allele", "scv_assertion", "condition", "xref"), 2L
  ),
  record_key = paste0(
    rep(c("release-old", "release-new"), each = 5L), "|",
    rep(c("variation", "allele", "scv", "condition", "xref"), 2L)
  ),
  record_ordinal = 1,
  vcv_accession = "VCV000000101",
  scv_entity_id = c(
    NA, NA, "old-assertion", "old-assertion", "old-assertion",
    NA, NA, "new-assertion", "new-assertion", "new-assertion"
  ),
  entity_id = c(
    "old-variation", "old-allele", "old-assertion", "old-condition", "old-xref",
    "new-variation", "new-allele", "new-assertion", "new-condition", "new-xref"
  ),
  parent_type = c(
    NA, NA, NA, "scv_assertion", "condition",
    NA, NA, NA, "scv_assertion", "condition"
  ),
  parent_id = c(
    NA, NA, NA, "old-assertion", "old-condition",
    NA, NA, NA, "new-assertion", "new-condition"
  ),
  variation_id = c(101, rep(NA, 4), 101, rep(NA, 4)),
  allele_id = c(NA, 201, rep(NA, 3), NA, 201, rep(NA, 3)),
  source_ordinal = c(NA, NA, 1, NA, NA, NA, NA, 1, NA, NA),
  accession = c(NA, NA, "SCV000000101", rep(NA, 2), NA, NA, "SCV000000101", rep(NA, 2)),
  version = c(NA, NA, 1, NA, NA, NA, NA, 2, NA, NA),
  classification = c(NA, NA, "Pathogenic", rep(NA, 2), NA, NA, "Pathogenic", rep(NA, 2)),
  review_status = c(
    NA, NA, "criteria provided, single submitter", NA, NA,
    NA, NA, "criteria provided, single submitter", NA, NA
  ),
  date_last_evaluated = as.Date(c(
    NA, NA, "2020-01-01", NA, NA, NA, NA, "2024-01-01", NA, NA
  )),
  context_type = c(
    NA, NA, NA, "scv_assertion", "condition",
    NA, NA, NA, "scv_assertion", "condition"
  ),
  context_id = c(
    NA, NA, NA, "old-assertion", "old-condition",
    NA, NA, NA, "new-assertion", "new-condition"
  ),
  preferred_name = c(
    rep(NA, 3), "Old disease label", NA,
    rep(NA, 3), "Updated disease label", NA
  ),
  database_name = c(rep(NA, 4), "OMIM", rep(NA, 4), "OMIM"),
  database_id = c(rep(NA, 4), "123456", rep(NA, 4), "123456")
))
stable_keys <- DBI::dbGetQuery(con, "
  SELECT release_id, disease_key
  FROM clinvar_disease_submissions
  WHERE vcv_accession = 'VCV000000101'
  ORDER BY release_id
")
expect_equal(stable_keys$disease_key, c("omim:123456", "omim:123456"))

# A replacement SCV version is reduced to the highest version for the same
# assertion identity. A withdrawn assertion is present in the old release and
# absent, rather than silently carried forward, in the new release.
DBI::dbAppendTable(con, "clinvar", data.frame(
  release_id = rep(c("versioned", "withdraw-old", "withdraw-new"), each = 2L),
  record_kind = rep(c("variation", "allele"), 3L),
  record_key = paste0(
    rep(c("versioned", "withdraw-old", "withdraw-new"), each = 2L),
    "|", rep(c("variation", "allele"), 3L)
  ),
  record_ordinal = 1,
  vcv_accession = rep(
    c("VCV000000102", "VCV000000103", "VCV000000103"), each = 2L
  ),
  entity_id = c(
    "versioned-variation", "versioned-allele",
    "withdraw-old-variation", "withdraw-old-allele",
    "withdraw-new-variation", "withdraw-new-allele"
  ),
  variation_id = c(102, NA, 103, NA, 103, NA),
  allele_id = c(NA, 202, NA, 203, NA, 203)
))
DBI::dbAppendTable(con, "clinvar", data.frame(
  release_id = c("versioned", "versioned", "withdraw-old"),
  record_kind = "scv_assertion",
  record_key = c("versioned|scv|1", "versioned|scv|2", "withdraw-old|scv"),
  record_ordinal = 1,
  source_ordinal = c(1, 2, 1),
  vcv_accession = c("VCV000000102", "VCV000000102", "VCV000000103"),
  scv_entity_id = c(
    "versioned-assertion", "versioned-assertion", "withdraw-assertion"
  ),
  entity_id = c(
    "versioned-assertion", "versioned-assertion", "withdraw-assertion"
  ),
  assertion_id = c(10201, 10201, 10301),
  accession = c("SCV000000102", "SCV000000102", "SCV000000103"),
  version = c(1, 2, 1),
  classification = c("Pathogenic", "Benign", "Pathogenic"),
  review_status = "criteria provided, single submitter",
  date_last_evaluated = as.Date(c("2020-01-01", "2024-01-01", "2024-01-01"))
))
versioned <- DBI::dbGetQuery(con, "
  SELECT policy_classification, retained_scv_count
  FROM clinvar_policy_allele_decisions
  WHERE release_id = 'versioned'
")
expect_equal(versioned$policy_classification, "Benign")
expect_equal(versioned$retained_scv_count, 1)
withdrawn <- DBI::dbGetQuery(con, "
  SELECT release_id
  FROM clinvar_policy_allele_decisions
  WHERE release_id IN ('withdraw-old', 'withdraw-new')
")
expect_equal(withdrawn$release_id, "withdraw-old")

# Compound records attach policy evidence to the top-level allele only; a
# nested component allele must not acquire the parent decision independently.
DBI::dbAppendTable(con, "clinvar", data.frame(
  release_id = "compound",
  record_kind = c("variation", "allele", "allele", "scv_assertion"),
  record_key = c(
    "compound|variation", "compound|root", "compound|child", "compound|scv"
  ),
  record_ordinal = 1,
  source_ordinal = c(NA, NA, NA, 1),
  vcv_accession = "VCV000000104",
  scv_entity_id = c(NA, NA, NA, "compound-assertion"),
  entity_id = c(
    "compound-variation", "compound-root", "compound-child",
    "compound-assertion"
  ),
  variation_id = c(104, NA, NA, NA),
  parent_allele_entity_id = c(NA, NA, "compound-root", NA),
  allele_id = c(NA, 204, 205, NA),
  accession = c(NA, NA, NA, "SCV000000104"),
  version = c(NA, NA, NA, 1),
  classification = c(NA, NA, NA, "Pathogenic"),
  review_status = c(NA, NA, NA, "criteria provided, single submitter"),
  date_last_evaluated = as.Date(c(NA, NA, NA, "2024-01-01"))
))
compound <- DBI::dbGetQuery(con, "
  SELECT allele_id
  FROM clinvar_policy_allele_decisions
  WHERE release_id = 'compound'
")
expect_equal(compound$allele_id, 204)

# GRCh38 mitochondrial source chromosome MT is exported as chrM.
DBI::dbExecute(con, "
  INSERT INTO clinvar_releases (release_id, source_path)
  VALUES ('mitochondrial', 'synthetic-release-fixture')
")
DBI::dbAppendTable(con, "clinvar", data.frame(
  release_id = "mitochondrial",
  record_kind = c("variation", "allele", "location", "scv_assertion"),
  record_key = paste0("mitochondrial|", c("variation", "allele", "location", "scv")),
  record_ordinal = 1,
  source_ordinal = c(NA, NA, NA, 1),
  vcv_accession = "VCV000000105",
  scv_entity_id = c(NA, NA, NA, "mitochondrial-assertion"),
  entity_id = c(
    "mitochondrial-variation", "mitochondrial-allele",
    "mitochondrial-location", "mitochondrial-assertion"
  ),
  parent_type = c(NA, NA, "allele", NA),
  parent_id = c(NA, NA, "mitochondrial-allele", NA),
  variation_id = c(105, NA, NA, NA),
  allele_id = c(NA, 205, NA, NA),
  assembly = c(NA, NA, "GRCh38", NA),
  chromosome = c(NA, NA, "MT", NA),
  position_vcf = c(NA, NA, 100, NA),
  reference_allele_vcf = c(NA, NA, "A", NA),
  alternate_allele_vcf = c(NA, NA, "G", NA),
  accession = c(NA, NA, NA, "SCV000000105"),
  version = c(NA, NA, NA, 1),
  classification = c(NA, NA, NA, "Pathogenic"),
  review_status = c(NA, NA, NA, "criteria provided, single submitter"),
  date_last_evaluated = as.Date(c(NA, NA, NA, "2024-01-01"))
))
mitochondrial_path <- tempfile(fileext = ".parquet")
rclinvarbitration_export_clinvarbitration_parquet(
  con, mitochondrial_path, "mitochondrial", "GRCh38"
)
mitochondrial <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT * FROM read_parquet(",
    as.character(DBI::dbQuoteString(con, mitochondrial_path)), ")"
  )
)
expect_equal(mitochondrial$contig, "chrM")
expect_equal(mitochondrial$position, 100)
unlink(mitochondrial_path)

DBI::dbDisconnect(con, shutdown = TRUE)
