/* Concrete streaming scanner for PubMed baseline and update XML. This is
 * included by rclinvarbitration_extension.c after its common DuckDB helpers.
 * It deliberately recognizes PubmedArticle, PubmedBookArticle, and
 * DeleteCitation rather than exposing parser nodes or a reusable XML object model.
 */

typedef struct rpubmed_value {
    char *entity_type;
    char *section;
    char *text_value;
    char *identifier_source;
    char *identifier;
    uint64_t citation_ordinal;
} rpubmed_value_t;

typedef struct rpubmed_record {
    uint64_t record_ordinal;
    uint64_t entity_ordinal;
    char *pmid;
    char *article_id_pmid;
    char *article_title;
    char *publication_date;
    char *source_date;
    bool is_deleted;
    char **delete_pmids;
    size_t delete_pmid_count;
    size_t delete_pmid_capacity;
    uint64_t reference_ordinal;
    rpubmed_value_t *values;
    size_t value_count;
    size_t value_capacity;
} rpubmed_record_t;

typedef struct rpubmed_row {
    uint64_t record_ordinal;
    uint64_t entity_ordinal;
    char *pmid;
    char *entity_type;
    char *section;
    char *text_value;
    char *identifier_source;
    char *identifier;
    uint64_t citation_ordinal;
    char *article_title;
    char *publication_date;
    char *source_date;
    bool is_deleted;
} rpubmed_row_t;

typedef struct rpubmed_stack_entry {
    char *name;
    char *label;
    char *nlm_category;
    char *id_type;
    char *ui;
    char *pub_status;
    uint64_t reference_ordinal;
    char *text;
    size_t text_length;
    size_t text_capacity;
    char *year;
    char *month;
    char *day;
    char *medline_date;
} rpubmed_stack_entry_t;

typedef struct rpubmed_scan_state {
    xmlTextReaderPtr reader;
    rpubmed_row_t *rows;
    size_t row_count;
    size_t row_capacity;
    size_t row_pos;
    rpubmed_stack_entry_t *stack;
    size_t stack_count;
    size_t stack_capacity;
    rpubmed_record_t record;
    uint64_t record_ordinal;
    int active_record;
    int finished;
    char error[RCLINVAR_ERROR_SIZE];
} rpubmed_scan_state_t;

static void rpubmed_set_error(rpubmed_scan_state_t *state, const char *message) {
    if (!state || state->error[0]) return;
    snprintf(state->error, sizeof(state->error), "%s",
             message ? message : "PubMed XML parser failed");
}

static char *rpubmed_trim_copy(const char *text) {
    const unsigned char *begin;
    const unsigned char *end;
    char *out;
    size_t length;
    if (!text) return NULL;
    begin = (const unsigned char *)text;
    while (*begin && isspace(*begin)) begin++;
    end = begin + strlen((const char *)begin);
    while (end > begin && isspace(end[-1])) end--;
    if (end == begin) return NULL;
    length = (size_t)(end - begin);
    out = (char *)malloc(length + 1U);
    if (!out) return NULL;
    memcpy(out, begin, length);
    out[length] = '\0';
    return out;
}

static int rpubmed_equal_ci(const char *left, const char *right) {
    size_t i;
    if (!left || !right) return 0;
    for (i = 0; left[i] && right[i]; i++) {
        if (tolower((unsigned char)left[i]) != tolower((unsigned char)right[i])) return 0;
    }
    return left[i] == '\0' && right[i] == '\0';
}

static int rpubmed_prefix_ci(const char *text, const char *prefix) {
    size_t i;
    if (!text || !prefix) return 0;
    for (i = 0; prefix[i]; i++) {
        if (!text[i] || tolower((unsigned char)text[i]) !=
            tolower((unsigned char)prefix[i])) return 0;
    }
    return 1;
}

static void rpubmed_value_clear(rpubmed_value_t *value) {
    if (!value) return;
    free(value->entity_type);
    free(value->section);
    free(value->text_value);
    free(value->identifier_source);
    free(value->identifier);
    memset(value, 0, sizeof(*value));
}

static void rpubmed_record_clear(rpubmed_record_t *record) {
    size_t i;
    if (!record) return;
    free(record->pmid);
    free(record->article_id_pmid);
    for (i = 0; i < record->delete_pmid_count; i++) free(record->delete_pmids[i]);
    free(record->delete_pmids);
    free(record->article_title);
    free(record->publication_date);
    free(record->source_date);
    for (i = 0; i < record->value_count; i++) rpubmed_value_clear(&record->values[i]);
    free(record->values);
    memset(record, 0, sizeof(*record));
}

static int rpubmed_record_set_text(rpubmed_scan_state_t *state, char **slot,
                                   const char *text, int replace) {
    char *value;
    if (!slot || !text || rclinvar_is_whitespace(text)) return 1;
    value = rpubmed_trim_copy(text);
    if (!value) {
        rpubmed_set_error(state, "out of memory copying PubMed text");
        return 0;
    }
    if (*slot && !replace) {
        free(value);
        return 1;
    }
    free(*slot);
    *slot = value;
    (void)state;
    return 1;
}

static char *rpubmed_copy_valid_pmid(rpubmed_scan_state_t *state, const char *text) {
    char *pmid;
    size_t i;
    if (!text || rclinvar_is_whitespace(text)) {
        rpubmed_set_error(state, "PubMed PMID must be a non-empty decimal identifier");
        return NULL;
    }
    pmid = rpubmed_trim_copy(text);
    if (!pmid) {
        rpubmed_set_error(state, "out of memory copying PubMed PMID");
        return NULL;
    }
    for (i = 0; pmid[i]; i++) {
        if (!isdigit((unsigned char)pmid[i])) {
            free(pmid);
            rpubmed_set_error(state, "PubMed PMID must be a non-empty decimal identifier");
            return NULL;
        }
    }
    return pmid;
}

static int rpubmed_assign_pmid(rpubmed_scan_state_t *state, char **slot,
                               const char *text, const char *label) {
    char *pmid = rpubmed_copy_valid_pmid(state, text);
    if (!pmid) return 0;
    if (*slot) {
        if (strcmp(*slot, pmid)) {
            free(pmid);
            rpubmed_set_error(state, label);
            return 0;
        }
        free(pmid);
        return 1;
    }
    *slot = pmid;
    return 1;
}

static int rpubmed_record_set_authoritative_pmid(rpubmed_scan_state_t *state,
                                                  const char *text) {
    if (!rpubmed_assign_pmid(
            state, &state->record.pmid, text,
            "PubMed source record has conflicting authoritative PMIDs")) return 0;
    if (state->record.article_id_pmid &&
        strcmp(state->record.pmid, state->record.article_id_pmid)) {
        rpubmed_set_error(state, "MedlineCitation PMID does not match ArticleId IdType=pubmed");
        return 0;
    }
    return 1;
}

static int rpubmed_record_set_article_id_pmid(rpubmed_scan_state_t *state,
                                               const char *text) {
    if (!rpubmed_assign_pmid(
            state, &state->record.article_id_pmid, text,
            "PubMed source record has conflicting ArticleId IdType=pubmed values")) return 0;
    if (state->record.pmid &&
        strcmp(state->record.pmid, state->record.article_id_pmid)) {
        rpubmed_set_error(state, "MedlineCitation PMID does not match ArticleId IdType=pubmed");
        return 0;
    }
    return 1;
}

static int rpubmed_record_add_delete_pmid(rpubmed_scan_state_t *state,
                                          const char *text) {
    rpubmed_record_t *record = &state->record;
    char *pmid = rpubmed_copy_valid_pmid(state, text);
    char **pmids;
    size_t capacity;
    size_t i;
    if (!pmid) return 0;
    for (i = 0; i < record->delete_pmid_count; i++) {
        if (!strcmp(record->delete_pmids[i], pmid)) {
            free(pmid);
            rpubmed_set_error(state, "DeleteCitation repeats one PMID");
            return 0;
        }
    }
    if (record->delete_pmid_count == record->delete_pmid_capacity) {
        capacity = record->delete_pmid_capacity ? record->delete_pmid_capacity * 2U : 4U;
        if (capacity < record->delete_pmid_capacity ||
            capacity > SIZE_MAX / sizeof(*pmids)) {
            free(pmid);
            rpubmed_set_error(state, "DeleteCitation has too many PMIDs");
            return 0;
        }
        pmids = (char **)realloc(record->delete_pmids, capacity * sizeof(*pmids));
        if (!pmids) {
            free(pmid);
            rpubmed_set_error(state, "out of memory buffering DeleteCitation PMIDs");
            return 0;
        }
        memset(pmids + record->delete_pmid_capacity, 0,
               (capacity - record->delete_pmid_capacity) * sizeof(*pmids));
        record->delete_pmids = pmids;
        record->delete_pmid_capacity = capacity;
    }
    record->delete_pmids[record->delete_pmid_count++] = pmid;
    return 1;
}

static int rpubmed_record_add_value(rpubmed_scan_state_t *state,
                                    const char *entity_type, const char *section,
                                    const char *text_value,
                                    const char *identifier_source,
                                    const char *identifier,
                                    uint64_t citation_ordinal) {
    rpubmed_record_t *record = &state->record;
    rpubmed_value_t *values;
    rpubmed_value_t *value;
    size_t capacity;
    if (!entity_type) return 1;
    if (record->value_count == record->value_capacity) {
        capacity = record->value_capacity ? record->value_capacity * 2U : 8U;
        if (capacity < record->value_capacity ||
            capacity > SIZE_MAX / sizeof(*values)) {
            rpubmed_set_error(state, "PubMed article has too many scalar values");
            return 0;
        }
        values = (rpubmed_value_t *)realloc(record->values, capacity * sizeof(*values));
        if (!values) {
            rpubmed_set_error(state, "out of memory buffering PubMed article values");
            return 0;
        }
        memset(values + record->value_capacity, 0,
               (capacity - record->value_capacity) * sizeof(*values));
        record->values = values;
        record->value_capacity = capacity;
    }
    value = &record->values[record->value_count];
    value->entity_type = rclinvar_strdup(entity_type);
    value->section = rpubmed_trim_copy(section);
    value->text_value = rpubmed_trim_copy(text_value);
    value->identifier_source = rpubmed_trim_copy(identifier_source);
    value->identifier = rpubmed_trim_copy(identifier);
    value->citation_ordinal = citation_ordinal;
    if (!value->entity_type ||
        (section && !rclinvar_is_whitespace(section) && !value->section) ||
        (text_value && !rclinvar_is_whitespace(text_value) && !value->text_value) ||
        (identifier_source && !rclinvar_is_whitespace(identifier_source) && !value->identifier_source) ||
        (identifier && !rclinvar_is_whitespace(identifier) && !value->identifier)) {
        rpubmed_value_clear(value);
        rpubmed_set_error(state, "out of memory copying PubMed scalar value");
        return 0;
    }
    record->value_count++;
    return 1;
}

static void rpubmed_row_clear(rpubmed_row_t *row) {
    if (!row) return;
    free(row->pmid);
    free(row->entity_type);
    free(row->section);
    free(row->text_value);
    free(row->identifier_source);
    free(row->identifier);
    free(row->article_title);
    free(row->publication_date);
    free(row->source_date);
    memset(row, 0, sizeof(*row));
}

static void rpubmed_rows_reset(rpubmed_scan_state_t *state) {
    size_t i;
    if (!state) return;
    for (i = state->row_pos; i < state->row_count; i++) rpubmed_row_clear(&state->rows[i]);
    state->row_count = 0;
    state->row_pos = 0;
}

static int rpubmed_rows_reserve(rpubmed_scan_state_t *state, size_t required) {
    rpubmed_row_t *rows;
    size_t capacity;
    if (required <= state->row_capacity) return 1;
    capacity = state->row_capacity ? state->row_capacity : 16U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U || capacity > SIZE_MAX / sizeof(*rows)) {
            rpubmed_set_error(state, "PubMed output queue is too large");
            return 0;
        }
        capacity *= 2U;
    }
    rows = (rpubmed_row_t *)realloc(state->rows, capacity * sizeof(*rows));
    if (!rows) {
        rpubmed_set_error(state, "out of memory allocating PubMed output queue");
        return 0;
    }
    memset(rows + state->row_capacity, 0,
           (capacity - state->row_capacity) * sizeof(*rows));
    state->rows = rows;
    state->row_capacity = capacity;
    return 1;
}

static int rpubmed_queue_row(rpubmed_scan_state_t *state, const char *pmid,
                             const char *entity_type, const char *section,
                             const char *text_value, const char *identifier_source,
                             const char *identifier, uint64_t citation_ordinal) {
    rpubmed_record_t *record = &state->record;
    rpubmed_row_t *row;
    if (!pmid || !entity_type ||
        !rpubmed_rows_reserve(state, state->row_count + 1U)) return 0;
    row = &state->rows[state->row_count];
    row->record_ordinal = record->record_ordinal;
    row->entity_ordinal = ++record->entity_ordinal;
    row->pmid = rclinvar_strdup(pmid);
    row->entity_type = rclinvar_strdup(entity_type);
    row->section = section ? rclinvar_strdup(section) : NULL;
    row->text_value = text_value ? rclinvar_strdup(text_value) : NULL;
    row->identifier_source = identifier_source ? rclinvar_strdup(identifier_source) : NULL;
    row->identifier = identifier ? rclinvar_strdup(identifier) : NULL;
    row->citation_ordinal = citation_ordinal;
    row->article_title = record->article_title ? rclinvar_strdup(record->article_title) : NULL;
    row->publication_date = record->publication_date ? rclinvar_strdup(record->publication_date) : NULL;
    row->source_date = record->source_date ? rclinvar_strdup(record->source_date) : NULL;
    row->is_deleted = record->is_deleted;
    if (!row->pmid || !row->entity_type ||
        (section && !row->section) || (text_value && !row->text_value) ||
        (identifier_source && !row->identifier_source) || (identifier && !row->identifier) ||
        (record->article_title && !row->article_title) ||
        (record->publication_date && !row->publication_date) ||
        (record->source_date && !row->source_date)) {
        rpubmed_row_clear(row);
        rpubmed_set_error(state, "out of memory queuing PubMed scalar row");
        return 0;
    }
    state->row_count++;
    return 1;
}

static int rpubmed_emit_record(rpubmed_scan_state_t *state) {
    rpubmed_record_t *record = &state->record;
    size_t i;
    if (record->is_deleted) {
        if (!record->delete_pmid_count) {
            rpubmed_set_error(state, "DeleteCitation is missing its PMID");
            return 0;
        }
        for (i = 0; i < record->delete_pmid_count; i++) {
            if (!rpubmed_queue_row(state, record->delete_pmids[i], "article",
                                   NULL, NULL, NULL, NULL, 0)) return 0;
        }
        return 1;
    }
    if (!record->pmid || !record->pmid[0]) {
        rpubmed_set_error(state, "PubMed source record is missing its PMID");
        return 0;
    }
    if (!rpubmed_queue_row(state, record->pmid, "article", NULL, NULL,
                           NULL, NULL, 0)) return 0;
    for (i = 0; i < record->value_count; i++) {
        rpubmed_value_t *value = &record->values[i];
        if (!rpubmed_queue_row(state, record->pmid, value->entity_type,
                               value->section, value->text_value,
                               value->identifier_source, value->identifier,
                               value->citation_ordinal)) return 0;
    }
    return 1;
}

static void rpubmed_stack_entry_clear(rpubmed_stack_entry_t *entry) {
    if (!entry) return;
    free(entry->name);
    free(entry->label);
    free(entry->nlm_category);
    free(entry->id_type);
    free(entry->ui);
    free(entry->pub_status);
    free(entry->text);
    free(entry->year);
    free(entry->month);
    free(entry->day);
    free(entry->medline_date);
    memset(entry, 0, sizeof(*entry));
}

static int rpubmed_stack_reserve(rpubmed_scan_state_t *state, size_t required) {
    rpubmed_stack_entry_t *stack;
    size_t capacity;
    if (required <= state->stack_capacity) return 1;
    capacity = state->stack_capacity ? state->stack_capacity : 32U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U || capacity > SIZE_MAX / sizeof(*stack)) {
            rpubmed_set_error(state, "PubMed XML nesting is too deep");
            return 0;
        }
        capacity *= 2U;
    }
    stack = (rpubmed_stack_entry_t *)realloc(state->stack, capacity * sizeof(*stack));
    if (!stack) {
        rpubmed_set_error(state, "out of memory allocating PubMed XML stack");
        return 0;
    }
    memset(stack + state->stack_capacity, 0,
           (capacity - state->stack_capacity) * sizeof(*stack));
    state->stack = stack;
    state->stack_capacity = capacity;
    return 1;
}

static int rpubmed_name_collects_text(const char *name) {
    return name && (!strcmp(name, "PMID") || !strcmp(name, "ArticleTitle") ||
                    !strcmp(name, "AbstractText") || !strcmp(name, "ArticleId") ||
                    !strcmp(name, "DescriptorName") || !strcmp(name, "QualifierName") ||
                    !strcmp(name, "Keyword") || !strcmp(name, "Year") ||
                    !strcmp(name, "Month") || !strcmp(name, "Day") ||
                    !strcmp(name, "MedlineDate"));
}

static int rpubmed_append_to_entry(rpubmed_scan_state_t *state,
                                   rpubmed_stack_entry_t *entry, const char *text) {
    char *buffer;
    size_t length;
    size_t required;
    size_t capacity;
    if (!entry || !text) return 1;
    length = strlen(text);
    if (!length) return 1;
    if (length > SIZE_MAX - entry->text_length - 1U) {
        rpubmed_set_error(state, "PubMed XML text is too large");
        return 0;
    }
    required = entry->text_length + length + 1U;
    if (required > entry->text_capacity) {
        capacity = entry->text_capacity ? entry->text_capacity : 64U;
        while (capacity < required) {
            if (capacity > SIZE_MAX / 2U) {
                rpubmed_set_error(state, "PubMed XML text is too large");
                return 0;
            }
            capacity *= 2U;
        }
        buffer = (char *)realloc(entry->text, capacity);
        if (!buffer) {
            rpubmed_set_error(state, "out of memory buffering PubMed XML text");
            return 0;
        }
        entry->text = buffer;
        entry->text_capacity = capacity;
    }
    memcpy(entry->text + entry->text_length, text, length);
    entry->text_length += length;
    entry->text[entry->text_length] = '\0';
    return 1;
}

static int rpubmed_append_text(rpubmed_scan_state_t *state, const char *text) {
    size_t i;
    for (i = 0; i < state->stack_count; i++) {
        rpubmed_stack_entry_t *entry = &state->stack[i];
        if (rpubmed_name_collects_text(entry->name) &&
            !rpubmed_append_to_entry(state, entry, text)) return 0;
    }
    return 1;
}

static int rpubmed_stack_has_name(const rpubmed_scan_state_t *state, const char *name) {
    size_t i;
    if (!state || !name) return 0;
    for (i = state->stack_count; i > 0; i--) {
        if (state->stack[i - 1U].name && !strcmp(state->stack[i - 1U].name, name)) return 1;
    }
    return 0;
}

static uint64_t rpubmed_reference_ordinal(const rpubmed_scan_state_t *state) {
    size_t i;
    if (!state) return 0;
    for (i = state->stack_count; i > 0; i--) {
        const rpubmed_stack_entry_t *entry = &state->stack[i - 1U];
        if (entry->name && !strcmp(entry->name, "Reference")) {
            return entry->reference_ordinal;
        }
    }
    return 0;
}

static rpubmed_stack_entry_t *rpubmed_nearest_date(rpubmed_scan_state_t *state) {
    size_t i;
    for (i = state->stack_count; i > 0; i--) {
        rpubmed_stack_entry_t *entry = &state->stack[i - 1U];
        if (entry->name && (!strcmp(entry->name, "PubDate") ||
                            !strcmp(entry->name, "ArticleDate") ||
                            !strcmp(entry->name, "PubMedPubDate"))) return entry;
    }
    return NULL;
}

static int rpubmed_set_component(rpubmed_scan_state_t *state, char **slot,
                                 const char *text) {
    char *value;
    if (!text || rclinvar_is_whitespace(text)) return 1;
    value = rpubmed_trim_copy(text);
    if (!value) {
        rpubmed_set_error(state, "out of memory copying PubMed date component");
        return 0;
    }
    free(*slot);
    *slot = value;
    (void)state;
    return 1;
}

static int rpubmed_month_number(const char *month) {
    static const char *const names[] = {
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    };
    size_t i;
    char *end = NULL;
    long numeric;
    if (!month || !month[0]) return 0;
    numeric = strtol(month, &end, 10);
    if (end && *end == '\0' && numeric >= 1L && numeric <= 12L) return (int)numeric;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (rpubmed_equal_ci(month, names[i]) || rpubmed_prefix_ci(month, names[i])) {
            return (int)i + 1;
        }
    }
    return 0;
}

static char *rpubmed_date_text(const rpubmed_stack_entry_t *entry) {
    int month;
    int written;
    size_t length;
    char *out;
    if (!entry) return NULL;
    if (!entry->year && entry->medline_date) return rclinvar_strdup(entry->medline_date);
    if (!entry->year) return NULL;
    month = rpubmed_month_number(entry->month);
    if (!entry->month) return rclinvar_strdup(entry->year);
    if (!month) {
        written = snprintf(NULL, 0, "%s-%s", entry->year, entry->month);
    } else if (!entry->day) {
        written = snprintf(NULL, 0, "%s-%02d", entry->year, month);
    } else {
        written = snprintf(NULL, 0, "%s-%02d-%s", entry->year, month, entry->day);
    }
    if (written < 0) return NULL;
    length = (size_t)written + 1U;
    out = (char *)malloc(length);
    if (!out) return NULL;
    if (!month) snprintf(out, length, "%s-%s", entry->year, entry->month);
    else if (!entry->day) snprintf(out, length, "%s-%02d", entry->year, month);
    else snprintf(out, length, "%s-%02d-%s", entry->year, month, entry->day);
    return out;
}

static int rpubmed_assign_date(rpubmed_scan_state_t *state,
                               const rpubmed_stack_entry_t *entry) {
    char *value;
    char **slot = NULL;
    int replace = 0;
    if (!entry || !entry->name) return 1;
    if (!strcmp(entry->name, "ArticleDate")) {
        slot = &state->record.publication_date;
        replace = 1;
    } else if (!strcmp(entry->name, "PubDate")) {
        slot = &state->record.publication_date;
    } else if (!strcmp(entry->name, "PubMedPubDate")) {
        slot = &state->record.source_date;
        replace = entry->pub_status && rpubmed_equal_ci(entry->pub_status, "pubmed");
    } else {
        return 1;
    }
    value = rpubmed_date_text(entry);
    if (!value) return 1;
    if (*slot && !replace) {
        free(value);
        return 1;
    }
    free(*slot);
    *slot = value;
    return 1;
}

static int rpubmed_add_cited_pmid(rpubmed_scan_state_t *state,
                                   const char *text, uint64_t citation_ordinal) {
    char *pmid = rpubmed_copy_valid_pmid(state, text);
    int ok;
    if (!pmid) return 0;
    ok = rpubmed_record_add_value(
        state, "cited_identifier", NULL, NULL, "pmid", pmid, citation_ordinal
    );
    free(pmid);
    return ok;
}

static int rpubmed_process_entry(rpubmed_scan_state_t *state,
                                 rpubmed_stack_entry_t *entry) {
    const char *text = entry->text;
    rpubmed_stack_entry_t *date;
    uint64_t citation_ordinal;
    int in_reference;
    if (!entry || !entry->name) return 1;
    if (!strcmp(entry->name, "Year") || !strcmp(entry->name, "Month") ||
        !strcmp(entry->name, "Day") || !strcmp(entry->name, "MedlineDate")) {
        date = rpubmed_nearest_date(state);
        if (date) {
            if (!strcmp(entry->name, "Year") && !rpubmed_set_component(state, &date->year, text)) return 0;
            if (!strcmp(entry->name, "Month") && !rpubmed_set_component(state, &date->month, text)) return 0;
            if (!strcmp(entry->name, "Day") && !rpubmed_set_component(state, &date->day, text)) return 0;
            if (!strcmp(entry->name, "MedlineDate") && !rpubmed_set_component(state, &date->medline_date, text)) return 0;
        }
    }
    if (!strcmp(entry->name, "PubDate") || !strcmp(entry->name, "ArticleDate") ||
        !strcmp(entry->name, "PubMedPubDate")) return rpubmed_assign_date(state, entry);
    if (!text || !text[0]) return 1;
    in_reference = rpubmed_stack_has_name(state, "Reference");
    citation_ordinal = in_reference ? rpubmed_reference_ordinal(state) : 0;
    if (!strcmp(entry->name, "PMID")) {
        if (state->record.is_deleted) return rpubmed_record_add_delete_pmid(state, text);
        if (in_reference) return rpubmed_add_cited_pmid(state, text, citation_ordinal);
        if (rpubmed_stack_has_name(state, "MedlineCitation") ||
            rpubmed_stack_has_name(state, "BookDocument")) {
            return rpubmed_record_set_authoritative_pmid(state, text);
        }
        rpubmed_set_error(state, "PubMed PMID appears outside MedlineCitation or BookDocument");
        return 0;
    }
    if (!strcmp(entry->name, "ArticleTitle")) {
        return rpubmed_record_set_text(state, &state->record.article_title, text, 1);
    }
    if (!strcmp(entry->name, "AbstractText")) {
        const char *section = entry->label ? entry->label : entry->nlm_category;
        return rpubmed_record_add_value(state, "abstract", section, text, NULL, NULL, 0);
    }
    if (!strcmp(entry->name, "ArticleId")) {
        if (entry->id_type && rpubmed_equal_ci(entry->id_type, "pubmed")) {
            if (in_reference) return rpubmed_add_cited_pmid(state, text, citation_ordinal);
            if (!rpubmed_record_set_article_id_pmid(state, text)) return 0;
        }
        return rpubmed_record_add_value(
            state, in_reference ? "cited_identifier" : "identifier", NULL, NULL,
            entry->id_type, text, citation_ordinal
        );
    }
    if (!strcmp(entry->name, "DescriptorName")) {
        return rpubmed_record_add_value(state, "mesh", NULL, text, "descriptor", entry->ui, 0);
    }
    if (!strcmp(entry->name, "QualifierName")) {
        return rpubmed_record_add_value(state, "mesh", NULL, text, "qualifier", entry->ui, 0);
    }
    if (!strcmp(entry->name, "Keyword")) {
        return rpubmed_record_add_value(state, "keyword", NULL, text, NULL, NULL, 0);
    }
    return 1;
}

static int rpubmed_end_element(rpubmed_scan_state_t *state, const char *local_name);

static int rpubmed_start_element(rpubmed_scan_state_t *state, xmlTextReaderPtr reader,
                                 const char *local_name) {
    rpubmed_stack_entry_t *entry;
    if (!rpubmed_stack_reserve(state, state->stack_count + 1U)) return 0;
    entry = &state->stack[state->stack_count];
    memset(entry, 0, sizeof(*entry));
    entry->name = rclinvar_strdup(local_name);
    entry->label = rclinvar_attribute(reader, "Label");
    entry->nlm_category = rclinvar_attribute(reader, "NlmCategory");
    entry->id_type = rclinvar_attribute(reader, "IdType");
    entry->ui = rclinvar_attribute(reader, "UI");
    entry->pub_status = rclinvar_attribute(reader, "PubStatus");
    if (entry->name && !strcmp(entry->name, "Reference")) {
        entry->reference_ordinal = ++state->record.reference_ordinal;
    }
    if (!entry->name) {
        rpubmed_stack_entry_clear(entry);
        rpubmed_set_error(state, "out of memory copying PubMed XML element name");
        return 0;
    }
    state->stack_count++;
    if (xmlTextReaderIsEmptyElement(reader)) {
        if (!rpubmed_end_element(state, local_name)) return 0;
    }
    return 1;
}

static int rpubmed_end_element(rpubmed_scan_state_t *state, const char *local_name) {
    rpubmed_stack_entry_t *entry;
    int ending_record;
    if (!state->stack_count) {
        rpubmed_set_error(state, "PubMed XML element stack underflow");
        return 0;
    }
    entry = &state->stack[state->stack_count - 1U];
    if (!entry->name || strcmp(entry->name, local_name)) {
        rpubmed_set_error(state, "PubMed XML element stack is inconsistent");
        return 0;
    }
    if (!rpubmed_process_entry(state, entry)) return 0;
    ending_record = !strcmp(local_name, "PubmedArticle") ||
                    !strcmp(local_name, "PubmedBookArticle") ||
                    !strcmp(local_name, "DeleteCitation");
    if (ending_record && !rpubmed_emit_record(state)) return 0;
    rpubmed_stack_entry_clear(entry);
    state->stack_count--;
    if (ending_record) {
        rpubmed_record_clear(&state->record);
        state->active_record = 0;
    }
    return 1;
}

static int rpubmed_start_record(rpubmed_scan_state_t *state, xmlTextReaderPtr reader,
                                const char *local_name) {
    rpubmed_record_clear(&state->record);
    state->record.record_ordinal = ++state->record_ordinal;
    state->record.is_deleted = !strcmp(local_name, "DeleteCitation");
    state->active_record = 1;
    return rpubmed_start_element(state, reader, local_name);
}

static int rpubmed_scan_next(rpubmed_scan_state_t *state) {
    int rc;
    while (!state->finished && state->row_pos == state->row_count) {
        const xmlChar *local;
        const xmlChar *value;
        int node_type;
        rpubmed_rows_reset(state);
        rc = xmlTextReaderRead(state->reader);
        if (rc == 0) {
            state->finished = 1;
            return 0;
        }
        if (rc < 0) {
            const xmlError *error = xmlGetLastError();
            snprintf(state->error, sizeof(state->error), "PubMed XML parse error%s%s",
                     error && error->message ? ": " : "",
                     error && error->message ? error->message : "");
            return -1;
        }
        node_type = xmlTextReaderNodeType(state->reader);
        local = xmlTextReaderConstLocalName(state->reader);
        if (!local) continue;
        if (node_type == XML_READER_TYPE_ELEMENT) {
            if (!state->active_record) {
                if (xmlStrEqual(local, BAD_CAST "PubmedArticle") ||
                    xmlStrEqual(local, BAD_CAST "PubmedBookArticle") ||
                    xmlStrEqual(local, BAD_CAST "DeleteCitation")) {
                    if (!rpubmed_start_record(state, state->reader, (const char *)local)) return -1;
                }
            } else if (!rpubmed_start_element(state, state->reader, (const char *)local)) {
                return -1;
            }
        } else if (state->active_record && node_type == XML_READER_TYPE_END_ELEMENT) {
            if (!rpubmed_end_element(state, (const char *)local)) return -1;
        } else if (state->active_record &&
                   (node_type == XML_READER_TYPE_TEXT || node_type == XML_READER_TYPE_CDATA)) {
            value = xmlTextReaderConstValue(state->reader);
            if (value && !rpubmed_append_text(state, (const char *)value)) return -1;
        }
    }
    return state->row_pos < state->row_count ? 1 : 0;
}

static void rpubmed_scan_destroy(void *pointer) {
    rpubmed_scan_state_t *state = (rpubmed_scan_state_t *)pointer;
    size_t i;
    if (!state) return;
    if (state->reader) xmlFreeTextReader(state->reader);
    for (i = 0; i < state->row_count; i++) rpubmed_row_clear(&state->rows[i]);
    free(state->rows);
    for (i = 0; i < state->stack_count; i++) rpubmed_stack_entry_clear(&state->stack[i]);
    free(state->stack);
    rpubmed_record_clear(&state->record);
    free(state);
}

static void rpubmed_xml_bind(duckdb_bind_info info) {
    duckdb_value value = NULL;
    char *path = NULL;
    rclinvar_bind_state_t *state = NULL;
    if (duckdb_bind_get_parameter_count(info) != 1U) {
        duckdb_bind_set_error(info, "rclinvarbitration_pubmed_xml_rows() requires exactly one XML or XML.GZ path");
        return;
    }
    value = duckdb_bind_get_parameter(info, 0);
    path = value ? duckdb_get_varchar(value) : NULL;
    if (value) duckdb_destroy_value(&value);
    if (!path || !path[0]) {
        if (path) duckdb_free(path);
        duckdb_bind_set_error(info, "rclinvarbitration_pubmed_xml_rows() path must be a non-empty string");
        return;
    }
    state = (rclinvar_bind_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_free(path);
        duckdb_bind_set_error(info, "out of memory binding rclinvarbitration_pubmed_xml_rows()");
        return;
    }
    state->path = rclinvar_strdup(path);
    duckdb_free(path);
    if (!state->path) {
        rclinvar_bind_destroy(state);
        duckdb_bind_set_error(info, "out of memory copying PubMed XML path");
        return;
    }
    rclinvar_add_column(info, "record_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "entity_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "pmid", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "entity_type", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "section", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "text_value", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "identifier_source", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "identifier", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "citation_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "article_title", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "publication_date", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "source_date", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "is_deleted", DUCKDB_TYPE_BOOLEAN);
    duckdb_bind_set_bind_data(info, state, rclinvar_bind_destroy);
}

static void rpubmed_xml_init(duckdb_init_info info) {
    const rclinvar_bind_state_t *bind =
        (const rclinvar_bind_state_t *)duckdb_init_get_bind_data(info);
    rpubmed_scan_state_t *state;
    if (!bind || !bind->path) {
        duckdb_init_set_error(info, "rclinvarbitration_pubmed_xml_rows() bind state is missing");
        return;
    }
    state = (rpubmed_scan_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_init_set_error(info, "out of memory initializing PubMed XML scan");
        return;
    }
    if (rclinvar_is_gzip_path(bind->path)) {
        gzFile input = gzopen(bind->path, "rb");
        if (input) {
            state->reader = xmlReaderForIO(
                rclinvar_gzip_read, rclinvar_gzip_close, input, bind->path, NULL,
                XML_PARSE_NONET | XML_PARSE_COMPACT | XML_PARSE_NOENT
            );
            if (!state->reader) gzclose(input);
        }
    } else {
        state->reader = xmlReaderForFile(
            bind->path, NULL, XML_PARSE_NONET | XML_PARSE_COMPACT | XML_PARSE_NOENT
        );
    }
    if (!state->reader) {
        rpubmed_scan_destroy(state);
        duckdb_init_set_error(info, "failed to open or parse PubMed XML/XML.GZ input");
        return;
    }
    duckdb_init_set_max_threads(info, 1);
    duckdb_init_set_init_data(info, state, rpubmed_scan_destroy);
}

static void rpubmed_assign_string(duckdb_vector vector, idx_t row, const char *value) {
    if (value) duckdb_vector_assign_string_element(vector, row, value);
    else rclinvar_set_null(vector, row);
}

static void rpubmed_assign_row(duckdb_data_chunk output, idx_t row,
                               const rpubmed_row_t *source) {
    uint64_t *record = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 0));
    uint64_t *ordinal = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 1));
    uint64_t *citation = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 8));
    bool *deleted = (bool *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 12));
    record[row] = source->record_ordinal;
    ordinal[row] = source->entity_ordinal;
    citation[row] = source->citation_ordinal;
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 2), row, source->pmid);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 3), row, source->entity_type);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 4), row, source->section);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 5), row, source->text_value);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 6), row, source->identifier_source);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 7), row, source->identifier);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 9), row, source->article_title);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 10), row, source->publication_date);
    rpubmed_assign_string(duckdb_data_chunk_get_vector(output, 11), row, source->source_date);
    deleted[row] = source->is_deleted;
}

static void rpubmed_xml_function(duckdb_function_info info, duckdb_data_chunk output) {
    rpubmed_scan_state_t *state =
        (rpubmed_scan_state_t *)duckdb_function_get_init_data(info);
    idx_t count = 0;
    if (!state) {
        duckdb_function_set_error(info, "rclinvarbitration_pubmed_xml_rows() scan state is missing");
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    while (count < RCLINVAR_CHUNK_SIZE) {
        rpubmed_row_t row;
        int status;
        if (state->row_pos >= state->row_count) {
            status = rpubmed_scan_next(state);
            if (status < 0) {
                duckdb_function_set_error(info, state->error[0] ? state->error : "PubMed XML scan failed");
                duckdb_data_chunk_set_size(output, 0);
                return;
            }
            if (status == 0) break;
        }
        row = state->rows[state->row_pos];
        memset(&state->rows[state->row_pos], 0, sizeof(row));
        state->row_pos++;
        rpubmed_assign_row(output, count, &row);
        rpubmed_row_clear(&row);
        count++;
    }
    duckdb_data_chunk_set_size(output, count);
}

static bool rpubmed_register_xml_rows(duckdb_connection connection) {
    duckdb_table_function function = duckdb_create_table_function();
    duckdb_logical_type parameter_type;
    duckdb_state status;
    if (!function) return false;
    parameter_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    if (!parameter_type) {
        duckdb_destroy_table_function(&function);
        return false;
    }
    duckdb_table_function_set_name(function, "rclinvarbitration_pubmed_xml_rows");
    duckdb_table_function_add_parameter(function, parameter_type);
    duckdb_destroy_logical_type(&parameter_type);
    duckdb_table_function_set_bind(function, rpubmed_xml_bind);
    duckdb_table_function_set_init(function, rpubmed_xml_init);
    duckdb_table_function_set_function(function, rpubmed_xml_function);
    status = duckdb_register_table_function(connection, function);
    duckdb_destroy_table_function(&function);
    return status == DuckDBSuccess;
}
