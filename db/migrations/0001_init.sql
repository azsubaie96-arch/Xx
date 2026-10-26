-- 0001_init.sql — initial schema (PostgreSQL 18+: uses native uuidv7()).
--
-- Table groups:
--   1. Identity & auth          users, refresh_tokens
--   2. Content                  topics, hashtags, videos, video_topics, video_hashtags
--   3. Social graph             follows, likes, shares, blocks, user_interests
--   4. Experiments              experiments, experiment_variants, experiment_exposures
--   5. Serving & behaviour logs feed_requests, impressions, events, interactions  (partitioned by month)
--   6. Derived ranking state    user_affinities, video_stats, video_stats_hourly
--   7. Analytics rollups        app_sessions, daily_user_activity
--
-- Log tables (group 5) deliberately have no foreign keys: they are append-heavy,
-- integrity is enforced at ingestion, and user deletion is handled by a purge job
-- rather than cascades across hundreds of millions of rows.

CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------------------
-- 1. Identity & auth
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT uuidv7(),
    username        citext NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_.]{3,30}$'),
    email           citext NOT NULL UNIQUE,
    password_hash   text,                              -- argon2id; NULL for social-login-only accounts
    display_name    text NOT NULL DEFAULT '',
    bio             text NOT NULL DEFAULT '' CHECK (char_length(bio) <= 300),
    avatar_url      text,
    locale          text NOT NULL DEFAULT 'en',
    country         char(2),
    birth_date      date,                              -- age gating (decision D9)
    onboarded_at    timestamptz,                       -- set when onboarding finished or skipped
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);

CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    family_id   uuid NOT NULL,                         -- rotation chain; reuse of a rotated token revokes the family
    token_hash  bytea NOT NULL UNIQUE,                 -- SHA-256 of the opaque token; raw token never stored
    user_agent  text,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx   ON refresh_tokens (user_id);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);

-- ---------------------------------------------------------------------------
-- 2. Content
-- ---------------------------------------------------------------------------

-- Curated taxonomy (~20-40 topics): powers onboarding, cold start and diversity rules.
CREATE TABLE topics (
    id             smallint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    slug           text NOT NULL UNIQUE,
    name           text NOT NULL,
    is_onboarding  boolean NOT NULL DEFAULT true,
    sort_order     smallint NOT NULL DEFAULT 0
);

-- Free-form, creator-supplied.
CREATE TABLE hashtags (
    id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    tag         citext NOT NULL UNIQUE CHECK (char_length(tag) BETWEEN 1 AND 100),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE video_status     AS ENUM ('uploading', 'processing', 'ready', 'failed', 'removed');
CREATE TYPE video_visibility AS ENUM ('public', 'followers', 'private');

CREATE TABLE videos (
    id                 uuid PRIMARY KEY DEFAULT uuidv7(),
    creator_id         uuid NOT NULL REFERENCES users (id),
    status             video_status NOT NULL DEFAULT 'uploading',
    visibility         video_visibility NOT NULL DEFAULT 'public',
    caption            text NOT NULL DEFAULT '' CHECK (char_length(caption) <= 2200),
    language           text,
    primary_topic_id   smallint REFERENCES topics (id),
    duration_ms        integer CHECK (duration_ms > 0),
    width              integer,
    height             integer,
    provider           text NOT NULL,                  -- 'mux' | 'cloudflare' | 'self' (decision D3)
    provider_asset_id  text,
    playback_url       text,                           -- HLS manifest
    thumbnail_url      text,
    failure_reason     text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    published_at       timestamptz,                    -- set when status becomes 'ready'
    updated_at         timestamptz NOT NULL DEFAULT now(),
    removed_at         timestamptz
);
CREATE INDEX videos_creator_idx  ON videos (creator_id, created_at DESC);
CREATE INDEX videos_feedable_idx ON videos (published_at DESC) WHERE status = 'ready' AND visibility = 'public';
CREATE UNIQUE INDEX videos_provider_asset_uidx ON videos (provider, provider_asset_id) WHERE provider_asset_id IS NOT NULL;

CREATE TABLE video_topics (
    video_id  uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    topic_id  smallint NOT NULL REFERENCES topics (id),
    weight    real NOT NULL DEFAULT 1.0,
    source    text NOT NULL DEFAULT 'creator' CHECK (source IN ('creator', 'model', 'moderator')),
    PRIMARY KEY (video_id, topic_id)
);
CREATE INDEX video_topics_topic_idx ON video_topics (topic_id);

CREATE TABLE video_hashtags (
    video_id    uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    hashtag_id  bigint NOT NULL REFERENCES hashtags (id),
    PRIMARY KEY (video_id, hashtag_id)
);
CREATE INDEX video_hashtags_hashtag_idx ON video_hashtags (hashtag_id);

-- ---------------------------------------------------------------------------
-- 3. Social graph (canonical state; the matching events go to `events`)
-- ---------------------------------------------------------------------------

CREATE TABLE follows (
    follower_id  uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    followee_id  uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);
CREATE INDEX follows_followee_idx ON follows (followee_id, created_at DESC);

CREATE TABLE likes (
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    video_id    uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, video_id)
);
CREATE INDEX likes_video_idx ON likes (video_id);

CREATE TABLE shares (
    id             uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id        uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    video_id       uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    channel        text,                               -- 'copy_link' | 'messages' | 'whatsapp' | ...
    impression_id  uuid,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX shares_video_idx ON shares (video_id);

CREATE TABLE blocks (
    blocker_id  uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    blocked_id  uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id)
);

-- Explicit onboarding picks (cold start). Learned interests live in user_affinities.
CREATE TABLE user_interests (
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    topic_id    smallint NOT NULL REFERENCES topics (id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, topic_id)
);

-- ---------------------------------------------------------------------------
-- 4. Experiments (assignment = hash(salt || user_id) mod 10000 → variant bucket)
-- ---------------------------------------------------------------------------

CREATE TABLE experiments (
    id           uuid PRIMARY KEY DEFAULT uuidv7(),
    key          text NOT NULL UNIQUE,
    description  text NOT NULL DEFAULT '',
    status       text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'running', 'stopped')),
    salt         text NOT NULL,
    started_at   timestamptz,
    ended_at     timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE experiment_variants (
    experiment_id   uuid NOT NULL REFERENCES experiments (id) ON DELETE CASCADE,
    name            text NOT NULL,
    allocation_bp   integer NOT NULL CHECK (allocation_bp BETWEEN 0 AND 10000),  -- basis points
    ranker_version  text NOT NULL,
    params          jsonb NOT NULL DEFAULT '{}',        -- value-model weights, exploration rate, ...
    PRIMARY KEY (experiment_id, name)
);

-- First exposure per user, so retention can be cut by variant.
CREATE TABLE experiment_exposures (
    experiment_id     uuid NOT NULL REFERENCES experiments (id) ON DELETE CASCADE,
    user_id           uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    variant           text NOT NULL,
    first_exposed_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (experiment_id, user_id)
);

-- ---------------------------------------------------------------------------
-- 5. Serving & behaviour logs (partitioned monthly; the training data of the future)
-- ---------------------------------------------------------------------------

-- One row per GET /feed.
CREATE TABLE feed_requests (
    id                uuid NOT NULL,
    requested_at      timestamptz NOT NULL,
    user_id           uuid NOT NULL,
    session_id        uuid,
    ranker_version    text NOT NULL,
    feature_version   text NOT NULL,
    experiment_key    text,
    variant           text,
    candidate_counts  jsonb NOT NULL DEFAULT '{}',      -- {"trending": 120, "affinity_topic": 180, ...}
    context           jsonb NOT NULL DEFAULT '{}',      -- locale, local_hour, session_depth, is_new_user
    latency_ms        integer,
    PRIMARY KEY (id, requested_at)
) PARTITION BY RANGE (requested_at);
CREATE INDEX feed_requests_user_idx ON feed_requests (user_id, requested_at DESC);

-- One row per video served. id is a UUIDv7 generated at served_at, so
-- uuid_extract_timestamp(id) recovers the partition key for lookups by id alone.
CREATE TABLE impressions (
    id                uuid NOT NULL,
    served_at         timestamptz NOT NULL,
    request_id        uuid NOT NULL,
    user_id           uuid NOT NULL,
    video_id          uuid NOT NULL,
    position          smallint NOT NULL,               -- position within the request page
    session_position  integer,                         -- position within the app session
    candidate_source  text NOT NULL,
    is_exploration    boolean NOT NULL DEFAULT false,
    selection_prob    real,                            -- propensity, for bias correction in training
    score             real NOT NULL,
    predictions       jsonb NOT NULL,                  -- per-task p̂: {"complete": .41, "like": .05, ...}
    features          jsonb NOT NULL,                  -- feature vector as seen by the ranker
    PRIMARY KEY (id, served_at)
) PARTITION BY RANGE (served_at);
CREATE INDEX impressions_user_idx  ON impressions (user_id, served_at DESC);
CREATE INDEX impressions_video_idx ON impressions (video_id, served_at DESC);

-- Raw client events. id is the client-generated event_id: (id, occurred_at) dedupes retries.
CREATE TABLE events (
    id             uuid NOT NULL,
    occurred_at    timestamptz NOT NULL,
    received_at    timestamptz NOT NULL DEFAULT now(),
    user_id        uuid NOT NULL,
    session_id     uuid,
    type           text NOT NULL,
    impression_id  uuid,
    video_id       uuid,
    props          jsonb NOT NULL DEFAULT '{}',
    platform       text,
    app_version    text,
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX events_impression_idx ON events (impression_id) WHERE impression_id IS NOT NULL;
CREATE INDEX events_user_idx       ON events (user_id, occurred_at);
CREATE INDEX events_type_idx       ON events (type, occurred_at);

-- One row per impression: the folded outcome / training label (see docs/03-event-tracking.md §4).
CREATE TABLE interactions (
    impression_id        uuid NOT NULL,
    served_at            timestamptz NOT NULL,
    user_id              uuid NOT NULL,
    video_id             uuid NOT NULL,
    creator_id           uuid NOT NULL,
    duration_ms          integer NOT NULL,
    watch_ms             integer NOT NULL DEFAULT 0,
    first_pass_ms        integer NOT NULL DEFAULT 0,
    watch_ratio          real NOT NULL DEFAULT 0,
    loops                smallint NOT NULL DEFAULT 0,
    replays              smallint NOT NULL DEFAULT 0,
    completed            boolean NOT NULL DEFAULT false,
    fast_skip            boolean NOT NULL DEFAULT false,
    liked                boolean NOT NULL DEFAULT false,
    shared               boolean NOT NULL DEFAULT false,
    followed_creator     boolean NOT NULL DEFAULT false,
    exit_reason          text,
    value                real NOT NULL DEFAULT 0,
    value_model_version  text NOT NULL,
    last_event_at        timestamptz NOT NULL,
    finalized            boolean NOT NULL DEFAULT false,
    PRIMARY KEY (impression_id, served_at)
) PARTITION BY RANGE (served_at);
CREATE INDEX interactions_user_idx  ON interactions (user_id, served_at DESC);
CREATE INDEX interactions_video_idx ON interactions (video_id, served_at DESC);

-- ---------------------------------------------------------------------------
-- 6. Derived ranking state (rebuildable from group 5)
-- ---------------------------------------------------------------------------

-- Decayed interest scores. Decay is applied lazily: effective = score * exp(-(now - updated_at) / tau).
-- successes/trials are decayed Beta-posterior counts for Thompson sampling over topics (cold start).
CREATE TABLE user_affinities (
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    entity_type  text NOT NULL CHECK (entity_type IN ('topic', 'hashtag', 'creator')),
    entity_id    text NOT NULL,                        -- topic id, hashtag id or creator uuid, as text
    score        real NOT NULL DEFAULT 0,
    successes    real NOT NULL DEFAULT 0,
    trials       real NOT NULL DEFAULT 0,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, entity_type, entity_id)
);

-- Hourly counters; the 72h windows in video_stats are summed from here.
CREATE TABLE video_stats_hourly (
    video_id     uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    hour         timestamptz NOT NULL,
    impressions  integer NOT NULL DEFAULT 0,
    completions  integer NOT NULL DEFAULT 0,
    fast_skips   integer NOT NULL DEFAULT 0,
    replays      integer NOT NULL DEFAULT 0,
    likes        integer NOT NULL DEFAULT 0,
    shares       integer NOT NULL DEFAULT 0,
    follows      integer NOT NULL DEFAULT 0,
    watch_ms     bigint  NOT NULL DEFAULT 0,
    value_sum    double precision NOT NULL DEFAULT 0,
    PRIMARY KEY (video_id, hour)
);

CREATE TABLE video_stats (
    video_id           uuid PRIMARY KEY REFERENCES videos (id) ON DELETE CASCADE,
    -- all-time
    impressions        bigint NOT NULL DEFAULT 0,
    completions        bigint NOT NULL DEFAULT 0,
    fast_skips         bigint NOT NULL DEFAULT 0,
    replays            bigint NOT NULL DEFAULT 0,
    likes              bigint NOT NULL DEFAULT 0,
    shares             bigint NOT NULL DEFAULT 0,
    follows            bigint NOT NULL DEFAULT 0,
    watch_ms           bigint NOT NULL DEFAULT 0,
    value_sum          double precision NOT NULL DEFAULT 0,
    -- trailing 72h
    impressions_72h    bigint NOT NULL DEFAULT 0,
    completions_72h    bigint NOT NULL DEFAULT 0,
    fast_skips_72h     bigint NOT NULL DEFAULT 0,
    likes_72h          bigint NOT NULL DEFAULT 0,
    shares_72h         bigint NOT NULL DEFAULT 0,
    follows_72h        bigint NOT NULL DEFAULT 0,
    value_sum_72h      double precision NOT NULL DEFAULT 0,
    -- cold-start traffic tiers: 0,1,2 = exploration tiers, 3 = graduated, -1 = demoted
    exploration_tier   smallint NOT NULL DEFAULT 0,
    tier_impressions   integer NOT NULL DEFAULT 0,
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX video_stats_tier_idx ON video_stats (exploration_tier) WHERE exploration_tier BETWEEN 0 AND 2;

-- ---------------------------------------------------------------------------
-- 7. Analytics rollups (metric definitions live in later migrations as views)
-- ---------------------------------------------------------------------------

CREATE TABLE app_sessions (
    id             uuid PRIMARY KEY,                   -- client session_id
    user_id        uuid NOT NULL,
    started_at     timestamptz NOT NULL,
    ended_at       timestamptz,
    foreground_ms  bigint NOT NULL DEFAULT 0,
    impressions    integer NOT NULL DEFAULT 0,
    platform       text,
    app_version    text
);
CREATE INDEX app_sessions_user_idx ON app_sessions (user_id, started_at DESC);

CREATE TABLE daily_user_activity (
    day            date NOT NULL,
    user_id        uuid NOT NULL,
    sessions       integer NOT NULL DEFAULT 0,
    foreground_ms  bigint  NOT NULL DEFAULT 0,
    impressions    integer NOT NULL DEFAULT 0,
    completions    integer NOT NULL DEFAULT 0,
    fast_skips     integer NOT NULL DEFAULT 0,
    likes          integer NOT NULL DEFAULT 0,
    shares         integer NOT NULL DEFAULT 0,
    follows        integer NOT NULL DEFAULT 0,
    uploads        integer NOT NULL DEFAULT 0,
    PRIMARY KEY (day, user_id)
);
CREATE INDEX daily_user_activity_user_idx ON daily_user_activity (user_id, day);

-- ---------------------------------------------------------------------------
-- Partition management. A scheduled worker calls this daily; a missing partition
-- makes inserts fail loudly rather than silently landing in a catch-all.
-- ---------------------------------------------------------------------------

CREATE FUNCTION ensure_monthly_partitions(parent regclass, months_ahead integer DEFAULT 2)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    parent_name text := (SELECT relname FROM pg_class WHERE oid = parent);
    month_start date;
BEGIN
    FOR i IN 0..months_ahead LOOP
        month_start := (date_trunc('month', now()) + make_interval(months => i))::date;
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
            parent_name || '_' || to_char(month_start, 'YYYYMM'),
            parent,
            month_start,
            (month_start + interval '1 month')::date
        );
    END LOOP;
END;
$$;

SELECT ensure_monthly_partitions('feed_requests');
SELECT ensure_monthly_partitions('impressions');
SELECT ensure_monthly_partitions('events');
SELECT ensure_monthly_partitions('interactions');
