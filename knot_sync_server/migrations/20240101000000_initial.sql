CREATE TABLE IF NOT EXISTS projects (
    id VARCHAR PRIMARY KEY,
    name VARCHAR UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notes (
    id VARCHAR PRIMARY KEY,
    project_id VARCHAR NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    is_voice BOOLEAN NOT NULL DEFAULT FALSE,
    voice_path VARCHAR,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR PRIMARY KEY,
    amount DOUBLE PRECISION NOT NULL DEFAULT 0,
    tx_type VARCHAR NOT NULL DEFAULT 'debit',
    merchant VARCHAR NOT NULL DEFAULT '',
    account_mask VARCHAR,
    upi_ref VARCHAR,
    upi_id VARCHAR,
    balance DOUBLE PRECISION,
    date TIMESTAMPTZ,
    sender VARCHAR NOT NULL DEFAULT '',
    raw_body TEXT,
    emoji VARCHAR,
    category VARCHAR,
    is_organized BOOLEAN NOT NULL DEFAULT FALSE,
    reason VARCHAR,
    bank VARCHAR,
    source VARCHAR NOT NULL DEFAULT 'sms',
    confidence DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notes_project ON notes(project_id);
CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_tx_emoji ON transactions(emoji);

CREATE TABLE IF NOT EXISTS attachments (
    id VARCHAR PRIMARY KEY,
    project_id VARCHAR,
    note_id VARCHAR,
    filename VARCHAR NOT NULL,
    mime_type VARCHAR,
    size BIGINT DEFAULT 0,
    path VARCHAR NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_project ON attachments(project_id);
CREATE INDEX IF NOT EXISTS idx_attachments_filename ON attachments(filename);
