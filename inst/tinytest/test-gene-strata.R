con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)

DBI::dbExecute(con, "
  INSERT INTO clinvar
    (release_id, record_kind, record_key, record_ordinal, source_ordinal,
     vcv_accession, scv_entity_id, entity_id, parent_type, parent_id,
     variation_id, allele_id, gene_id, gene_symbol, accession, version,
     submitter_name, classification, review_status, date_last_evaluated,
     context_type, context_id, preferred_name, database_name, database_id)
  VALUES
    ('gene-strata', 'variation', 'variation|p', 1, NULL,
     'VCV-GENE-P', NULL, 'variation-p', NULL, NULL,
     1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'variation', 'variation|b', 2, NULL,
     'VCV-GENE-B', NULL, 'variation-b', NULL, NULL,
     2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'allele', 'allele|p', 1, NULL,
     'VCV-GENE-P', NULL, 'allele-p', NULL, NULL,
     1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'allele', 'allele|b', 2, NULL,
     'VCV-GENE-B', NULL, 'allele-b', NULL, NULL,
     2, 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'gene', 'gene|p', 1, NULL,
     'VCV-GENE-P', NULL, 'gene-p', 'allele', 'allele-p',
     NULL, NULL, 101, 'GENEP', NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'gene', 'gene|b', 2, NULL,
     'VCV-GENE-B', NULL, 'gene-b', 'allele', 'allele-b',
     NULL, NULL, 102, 'GENEB', NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'scv_assertion', 'scv|p', 1, 1,
     'VCV-GENE-P', 'assertion-p', 'assertion-p', NULL, NULL,
     NULL, NULL, NULL, NULL, 'SCV-GENE-P', 1, 'Expert lab',
     'Pathogenic', 'reviewed by expert panel', DATE '2026-01-01',
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'scv_assertion', 'scv|b', 2, 1,
     'VCV-GENE-B', 'assertion-b', 'assertion-b', NULL, NULL,
     NULL, NULL, NULL, NULL, 'SCV-GENE-B', 1, 'Clinical lab',
     'Benign', 'criteria provided, single submitter', DATE '2026-01-01',
     NULL, NULL, NULL, NULL, NULL),
    ('gene-strata', 'condition', 'condition|p', 1, NULL,
     'VCV-GENE-P', 'assertion-p', 'condition-p', 'scv_assertion', 'assertion-p',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     'scv_assertion', 'assertion-p', 'Disease P', 'MONDO', '0000001'),
    ('gene-strata', 'condition', 'condition|b', 2, NULL,
     'VCV-GENE-B', 'assertion-b', 'condition-b', 'scv_assertion', 'assertion-b',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
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
