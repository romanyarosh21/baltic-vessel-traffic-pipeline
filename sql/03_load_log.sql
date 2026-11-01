CREATE TABLE IF NOT EXISTS raw.load_log (
    source_file   text        PRIMARY KEY,
    status        text        NOT NULL CHECK (status IN ('complete', 'partial')),
    rows_loaded   bigint      NOT NULL,
    rows_skipped  bigint      NOT NULL DEFAULT 0,
    loaded_at     timestamptz NOT NULL DEFAULT now()
);