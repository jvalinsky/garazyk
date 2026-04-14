-- Initialize PLC database schema
-- Based on did-method-plc/packages/server/pg/script.sql

CREATE TABLE if not exists repo (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    null_hash bytea NOT NULL,
    current TEXT NOT NULL,
    history TEXT NOT NULL
);

CREATE TABLE if not exists rotation_key (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    owner TEXT NOT NULL REFERENCES repo(id),
    public_key bytea NOT NULL
);

CREATE TABLE if not exists operation (
    id BIGSERIAL PRIMARY KEY,
    repo TEXT NOT NULL REFERENCES repo(id),
    operation JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    signed_at TIMESTAMP WITH TIME ZONE,
    prev bytea NOT NULL,
    sig bytea NOT NULL,
    key_id TEXT NOT NULL REFERENCES rotation_key(id)
);

CREATE INDEX if not exists operation_repo_idx ON operation(repo);
CREATE INDEX if not exists operation_created_at_idx ON operation(created_at);
CREATE INDEX if not exists repo_current_idx ON repo(current);
CREATE INDEX if not exists rotation_key_owner_idx ON rotation_key(owner);

-- Create test account table for our PDS integration tests
CREATE TABLE if not exists test_accounts (
    id SERIAL PRIMARY KEY,
    did TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
