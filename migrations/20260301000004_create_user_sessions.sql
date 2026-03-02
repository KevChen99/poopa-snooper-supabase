-- Migration: user_sessions table
-- Tracks active sessions for concurrent login detection.
-- ended_at = NULL means session is still active.

CREATE TABLE user_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    ip_address      INET,
    user_agent      TEXT,
    device_hash     TEXT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user_active
    ON user_sessions(user_id) WHERE ended_at IS NULL;

CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
