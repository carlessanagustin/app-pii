-- LiteLLM Database Initialization Script
-- Security hardened PostgreSQL setup

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schema for better organization
CREATE SCHEMA IF NOT EXISTS litellm;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO litellm_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA litellm
GRANT USAGE, SELECT ON SEQUENCES TO litellm_user;

-- Security: Enable row-level security on tables (LiteLLM will create its own tables)
-- This is a template for when tables are created
-- ALTER TABLE litellm.your_table ENABLE ROW LEVEL SECURITY;

-- Create audit log function for tracking changes
CREATE OR REPLACE FUNCTION litellm.audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO litellm.audit_log (
            table_name,
            operation,
            old_data,
            changed_at,
            changed_by
        ) VALUES (
            TG_TABLE_NAME,
            TG_OP,
            row_to_json(OLD),
            NOW(),
            current_user
        );
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO litellm.audit_log (
            table_name,
            operation,
            old_data,
            new_data,
            changed_at,
            changed_by
        ) VALUES (
            TG_TABLE_NAME,
            TG_OP,
            row_to_json(OLD),
            row_to_json(NEW),
            NOW(),
            current_user
        );
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO litellm.audit_log (
            table_name,
            operation,
            new_data,
            changed_at,
            changed_by
        ) VALUES (
            TG_TABLE_NAME,
            TG_OP,
            row_to_json(NEW),
            NOW(),
            current_user
        );
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create audit log table
CREATE TABLE IF NOT EXISTS litellm.audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT NOW(),
    changed_by TEXT DEFAULT current_user
);

-- Create index for faster audit log queries
CREATE INDEX IF NOT EXISTS idx_audit_log_table ON litellm.audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON litellm.audit_log(changed_at);

-- Grant permissions to litellm_user
GRANT USAGE ON SCHEMA litellm TO litellm_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA litellm TO litellm_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA litellm TO litellm_user;

-- Security: Set secure defaults
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'mod';

-- Display confirmation
DO $$
BEGIN
    RAISE NOTICE 'LiteLLM database initialized successfully with security hardening';
END $$;
