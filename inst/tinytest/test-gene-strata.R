con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)

DBI::dbExecute(con, "
  INSERT INTO clinvar_variants
    (release_id, record_ordinal, vcv_accession, variation_id)
  VALUES ('gene-strata', 1, 'VCV-GENE-P', 1),
         ('gene-strata', 2, 'VCV-GENE-B', 2)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_alleles
    (release_id, record_ordinal, vcv_accession, allele_entity_id, allele_id)
  VALUES ('gene-strata', 1, 'VCV-GENE-P', 'allele-p', 1),
         ('gene-strata', 2, 'VCV-GENE-B', 'allele-b', 2)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_genes
    (release_id, record_ordinal, vcv_accession, allele_entity_id,
     gene_entity_id, gene_id, symbol)
  VALUES ('gene-strata', 1, 'VCV-GENE-P', 'allele-p', 'gene-p', 101, 'GENEP'),
         ('gene-strata', 2, 'VCV-GENE-B', 'allele-b', 'gene-b', 102, 'GENEB')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_scv_assertions
    (release_id, record_ordinal, source_ordinal, vcv_accession,
     assertion_entity_id, scv_accession, scv_version, submitter_name,
     classification, review_status, date_last_evaluated)
  VALUES ('gene-strata', 1, 1, 'VCV-GENE-P', 'assertion-p', 'SCV-GENE-P', 1,
          'Expert lab', 'Pathogenic', 'reviewed by expert panel',
          DATE '2026-01-01'),
         ('gene-strata', 2, 1, 'VCV-GENE-B', 'assertion-b', 'SCV-GENE-B', 1,
          'Clinical lab', 'Benign', 'criteria provided, single submitter',
          DATE '2026-01-01')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_conditions
    (release_id, record_ordinal, vcv_accession, scv_entity_id, condition_id,
     context_type, context_id, preferred_name, database_name, database_id)
  VALUES ('gene-strata', 1, 'VCV-GENE-P', 'assertion-p', 'condition-p',
          'scv_assertion', 'assertion-p', 'Disease P', 'MONDO', '0000001'),
         ('gene-strata', 2, 'VCV-GENE-B', 'assertion-b', 'condition-b',
          'scv_assertion', 'assertion-b', 'Disease B', 'MONDO', '0000002')
")

strata <- DBI::dbGetQuery(con, "
  SELECT symbol, clinvar_evidence_stratum
  FROM clinvar_gene_disease_summaries
  WHERE release_id = 'gene-strata'
  ORDER BY symbol
")
expect_equal(strata$symbol, c("GENEB", "GENEP"))
expect_equal(
  strata$clinvar_evidence_stratum,
  c("benign_only", "expert_reviewed_pathogenic")
)

DBI::dbDisconnect(con, shutdown = TRUE)
