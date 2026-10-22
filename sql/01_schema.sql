-- Bootstrap only. Add the final relational design in later numbered files.
-- PostgreSQL runs every *.sql file in this folder once when a Docker volume
-- is first created. The script is also safe to run repeatedly with psql.

CREATE SCHEMA IF NOT EXISTS parcel_tracking;

CREATE TABLE IF NOT EXISTS parcel_tracking.schema_migrations (
    version      TEXT PRIMARY KEY,
    applied_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description  TEXT NOT NULL
);

INSERT INTO parcel_tracking.schema_migrations (version, description)
VALUES ('001', 'Create bootstrap schema for parcel tracking')
ON CONFLICT (version) DO NOTHING;
