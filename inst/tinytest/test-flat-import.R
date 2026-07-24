submission_path <- system.file(
  "extdata", "submission_summary_fixture.txt",
  package = "RClinVarbitration", mustWork = TRUE
)
variant_path <- system.file(
  "extdata", "variant_summary_fixture.txt",
  package = "RClinVarbitration", mustWork = TRUE
)

con <- DBI::dbConnect(duckdb::duckdb())
parquet_path <- tempfile("rclinvarbitration-flat-", fileext = ".parquet")
imported <- rclinvarbitration_import_flat(
  con,
  submission_path,
  variant_path,
  release_id = "flat-fixture",
  parquet_path = parquet_path
)
expect_equal(imported$table_name, "clinvar")
expect_equal(imported$release_id, "flat-fixture")
expect_equal(imported$schema, "tidy")
expect_equal(imported$path, normalizePath(parquet_path))
expect_true(file.exists(parquet_path))
expect_equal(
  imported$counts$record_kind,
  c(
    "allele", "decision", "gene", "location", "rcv_assertion",
    "scv_assertion", "variation"
  )
)
expect_equal(imported$counts$rows, c(2, 1, 2, 3, 2, 2, 2))

records <- DBI::dbGetQuery(
  con,
  "SELECT * FROM clinvar ORDER BY record_kind, record_key"
)
expect_equal(nrow(records), 14L)
expect_equal(length(unique(records$record_key)), 14L)
expect_true(all(records$release_id == "flat-fixture"))
expect_equal(
  records$classification[records$record_kind == "decision"],
  "Pathogenic/Likely Pathogenic"
)
variations <- records[records$record_kind == "variation", ]
expect_equal(
  variations$classification[variations$variation_id == 201],
  "Pathogenic"
)
expect_equal(
  variations$number_of_submitters[variations$variation_id == 201],
  2
)
expect_equal(
  variations$date_last_evaluated[variations$variation_id == 202],
  as.Date("2026-01-02")
)
expect_equal(
  records$preferred_name[records$record_kind == "rcv_assertion"],
  c("Disease one", "Disease two")
)
expect_equal(
  records$description[records$record_kind == "scv_assertion"],
  c("Evidence one", "Evidence two")
)
expect_equal(
  records$gene_symbol[records$record_kind == "gene"],
  c("GENE1", "GENE2")
)
vcf <- DBI::dbGetQuery(con, "SELECT * FROM clinvar_vcf ORDER BY assembly")
expect_equal(vcf$assembly, c("GRCh37", "GRCh38"))
expect_equal(vcf$contig, c("1", "chr1"))
expect_equal(vcf$sequence_accession, c("NC_000001.10", "NC_000001.11"))
expect_equal(vcf$position, c(90, 100))
expect_equal(vcf$reference, c("A", "A"))
expect_equal(vcf$alternate, c("G", "G"))
expect_equal(vcf$start, c(90, 100))
expect_equal(vcf$stop, c(90, 100))
expect_equal(
  DBI::dbGetQuery(con, "
    SELECT count(*) AS n FROM clinvar
    WHERE record_kind = 'location' AND variation_id = 202
      AND position_vcf IS NULL AND reference_allele_vcf = 'na'
  ")$n,
  1
)

# Primary chromosomes receive assembly-conventional VCF names, while alternate
# placements retain their accession and X/Y placements remain separate rows.
DBI::dbExecute(con, "
  INSERT INTO clinvar (
    release_id, record_kind, record_key, record_ordinal, entity_id,
    parent_type, parent_id, assembly, chromosome, sequence_accession,
    position_vcf, reference_allele_vcf, alternate_allele_vcf
  ) VALUES
    ('flat-fixture', 'location', 'location|alt', 12, 'location:alt',
     'allele', 'allele:101', 'GRCh38', '1', 'NT_187361.1', 101, 'A', 'T'),
    ('flat-fixture', 'location', 'location|par-x', 13, 'location:par-x',
     'allele', 'allele:101', 'GRCh38', 'X', 'NC_000023.11', 10001, 'C', 'G'),
    ('flat-fixture', 'location', 'location|par-y', 14, 'location:par-y',
     'allele', 'allele:101', 'GRCh38', 'Y', 'NC_000024.10', 10001, 'C', 'G')
")
placement_names <- DBI::dbGetQuery(con, "
  SELECT coordinate_key, chromosome, sequence_accession, contig
  FROM clinvar_vcf
  WHERE coordinate_key IN ('location|alt', 'location|par-x', 'location|par-y')
  ORDER BY coordinate_key
")
expect_equal(
  placement_names$contig,
  c("NT_187361.1", "chrX", "chrY")
)
expect_equal(placement_names$chromosome, c("1", "X", "Y"))
compatibility_path <- tempfile(
  "rclinvarbitration-compatibility-", fileext = ".parquet"
)
rclinvarbitration_export_clinvarbitration_parquet(
  con, compatibility_path, "flat-fixture", assembly = "GRCh38"
)
compatibility_contigs <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT contig FROM read_parquet(",
    DBI::dbQuoteString(con, compatibility_path), ") ORDER BY contig"
  )
)$contig
expect_equal(compatibility_contigs, c("chr1", "chrX", "chrY"))
unlink(compatibility_path)
tidy_export_path <- tempfile(
  "rclinvarbitration-tidy-", fileext = ".parquet"
)
rclinvarbitration_export_clinvarbitration_parquet(
  con, tidy_export_path, "flat-fixture",
  assembly = "GRCh38", schema = "tidy"
)
expect_equal(
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM read_parquet(",
      DBI::dbQuoteString(con, tidy_export_path),
      ") WHERE record_kind = 'decision'"
    )
  )$n,
  1
)
unlink(tidy_export_path)
parquet_columns <- DBI::dbGetQuery(
  con,
  paste0(
    "DESCRIBE SELECT * FROM read_parquet(",
    DBI::dbQuoteString(con, parquet_path), ")"
  )
)$column_name
expect_false("release_id" %in% parquet_columns)
types <- DBI::dbGetQuery(con, "DESCRIBE clinvar")$column_type
expect_false(any(grepl("STRUCT|\\[\\]$", types)))
expect_error(
  rclinvarbitration_import_flat(
    con, submission_path, variant_path, "flat-fixture"
  ),
  "already exists"
)

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(parquet_path)

# One allele can have multiple assembly placements, including separate X and Y
# rows, and upstream gene lists can repeat the same gene. These remain distinct
# location facts but must not duplicate the allele-level decision or gene key.
duplicate_variant_path <- tempfile(
  "variant-summary-duplicate-fixture-", fileext = ".txt"
)
variant_lines <- readLines(variant_path, warn = FALSE)
header <- strsplit(variant_lines[[1L]], "\t", fixed = TRUE)[[1L]]
duplicate <- strsplit(variant_lines[[2L]], "\t", fixed = TRUE)[[1L]]
duplicate[match("ChromosomeAccession", header)] <- "NC_000024.10"
duplicate[match("Chromosome", header)] <- "Y"
duplicate[match("Start", header)] <- "10000"
duplicate[match("Stop", header)] <- "10000"
duplicate[match("PositionVCF", header)] <- "10000"
duplicate[match("GeneID", header)] <- "301;302;301"
duplicate[match("GeneSymbol", header)] <- "GENE1;GENE2;GENE1"
duplicate[match("HGNC_ID", header)] <- "HGNC:301;HGNC:302;HGNC:301"
writeLines(c(variant_lines, paste(duplicate, collapse = "\t")),
           duplicate_variant_path)
duplicate_con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_import_flat(
  duplicate_con, submission_path, duplicate_variant_path,
  release_id = "flat-duplicate-fixture", assembly = "GRCh38"
)
expect_equal(
  DBI::dbGetQuery(
    duplicate_con,
    "SELECT count(*) AS n FROM clinvar
     WHERE record_kind = 'location' AND allele_id = 101"
  )$n,
  2
)
expect_equal(
  DBI::dbGetQuery(
    duplicate_con,
    "SELECT count(*) AS n FROM clinvar
     WHERE record_kind = 'decision' AND allele_id = 101"
  )$n,
  1
)
expect_equal(
  DBI::dbGetQuery(
    duplicate_con,
    "SELECT count(*) AS n FROM clinvar
     WHERE record_kind = 'gene' AND allele_id = 101"
  )$n,
  2
)
expect_equal(
  DBI::dbGetQuery(
    duplicate_con,
    "SELECT count(*) - count(DISTINCT record_key) AS n FROM clinvar"
  )$n,
  0
)
DBI::dbDisconnect(duplicate_con, shutdown = TRUE)
unlink(duplicate_variant_path)
