# 06 — Phased Implementation Plan

Each phase ends with something that runs end-to-end and an explicit **exit
check**. We stop at the end of each phase for your review before starting the
next.

The order is deliberate. **Tracking comes before recommendations**, because the
ranker needs data. **The A/B framework ships with the first ranker**, so the
personalised feed's lift over a non-personalised baseline is measured from day
one rather than assumed.

---

## Phase 0 — Foundations (≈ 2–3 days)

* Monorepo layout, `docker-compose` (Postgres 18, Redis, MinIO), and a `Makefile`.
* API skeleton: config, DB pool, health check, structured logging, error model,
  and a migration runner applying `0001_init.sql` plus `0002_seed_topics`.
* Expo app shell with navigation, theme, and a generated API client.
* CI: ruff, mypy, pytest (with Postgres service), ESLint/tsc for mobile, and a
  check that migrations apply.
* `CLAUDE.md` updated with the real commands.

**Exit check:** `make dev` boots everything locally; CI is green on an empty
feature set.

## Phase 1 — MVP core: auth, upload, vertical feed (≈ 1–1.5 weeks)

* **Auth:** sign up, log in, refresh, log out; Argon2id; JWT plus rotating
  refresh tokens; secure token storage on device.
* **Upload:** pick or record, upload directly to the provider (D3), processing
  webhook, video status lifecycle, caption, topic picker, hashtags.
* **Feed v0:** a `ChronologicalRanker` (newest ready videos, with no repeats
  within a session) behind the `Ranker` interface. `GET /feed` already writes
  `feed_requests` and `impressions`.
* **Mobile:** full-screen vertical pager, player pool (±1), preloading,
  infinite scroll, tap to pause, mute toggle, basic profile page with the
  user's own videos.
* Seed script: about 200 test videos across topics, for development.

**Exit check:** on a real phone, a new user can sign up, upload a video, and see
it among the others in a smooth infinite vertical feed. Scrolling 100+ videos
does not grow memory.

## Phase 2 — Behaviour tracking and social actions (≈ 1 week)

* Like, unlike, share (native share sheet), follow, unfollow: endpoints and UI.
* Mobile `Tracker`: view sessions (`view_start`, `view_progress`, `view_end`),
  app session events, offline queue, batched flush, retry with idempotent IDs.
* `POST /v1/events/batch` ingestion: validation, deduplication, partition
  management job.
* Interaction aggregator → `interactions` with watch ratio, completion, fast
  skip, replays, like, share, follow, and value.
* `video_stats_hourly` and `video_stats` jobs.
* A debug screen (dev builds only) showing the live event stream.

**Exit check:** scripted test sessions (watch fully, skip, replay, like, share,
follow) yield the exact expected `interactions` rows. Event loss under
airplane-mode toggling is 0 %.

## Phase 3 — Recommendation engine v1: personalisation and cold start (≈ 1.5–2 weeks)

* Pipeline stages: context → candidate sources (trending, affinity_topic,
  affinity_creator, following, exploration) → filters → feature registry and
  builder → `heuristic_v1` ranker → value model → re-ranker.
* Affinity updater (lazy-decayed topic, hashtag, and creator affinities).
* Cold start: onboarding topic picker (D11), topic Thompson sampling, locale
  trending, new-video traffic tiers.
* Feature, prediction, and propensity logging on every impression.
* **Experiments:** hash-based assignment, `experiment_exposures`. The first
  experiment is `heuristic_v1` (90 %) vs `trending_baseline` (10 % holdout).
* Synthetic-user simulator. Bots with hidden topic preferences use the feed
  and react by rule. It checks that the feed converges on their preferences
  within N swipes. This is our automated test for "the algorithm learns".

**Exit check:** in the simulator, a new synthetic user's feed share of their
preferred topics rises from about 10 % (baseline) to over 60 % within 50 swipes.
Feed p95 is under 150 ms with 10k videos and 1k users seeded.

## Phase 4 — Analytics dashboard (≈ 1 week)

* SQL metric layer (`0003_analytics_views`) and rollup jobs.
* Dashboard pages:
  * **Retention:** DAU/WAU/MAU, stickiness, D1/D7/D30 cohort triangle, session
    length, sessions per user, split by onboarding path and experiment variant.
  * **Recommendation quality:** per ranker version, variant, candidate source,
    and new vs established users. Covers value per impression, completion,
    watch ratio, fast-skip, like, share, and follow rates, and items per session.
  * **Ecosystem:** catalogue coverage, creator exposure Gini, new-video
    graduation funnel through the traffic tiers, topic diversity.
  * **Experiments:** variant comparison with confidence intervals.
* Internal-only auth (admin role).

**Exit check:** every metric is reproducible from a documented SQL query, and
the `heuristic_v1` vs baseline experiment is readable from the dashboard.

## Phase 5 — First learned ranker (after ~1M labelled impressions)

* `ml/` dataset export (`impressions ⋈ interactions`, using logged features),
  train/validation split by time.
* LightGBM model per task, calibration, offline evaluation (AUC per task,
  NDCG@10 via the replay harness) against `heuristic_v1`.
* `LgbmRanker` behind the same interface. First in shadow mode (scores logged,
  not served), then in an A/B test.
* Daily retrain job with model versioning and automatic rollback when online
  metrics regress.

## Phase 6 — Scale and depth (driven by data and growth)

* Content moderation pipeline and reports (**required before public launch**, D9).
* Two-tower embedding retrieval (pgvector) and content embeddings for
  video cold start.
* Event streaming (Redpanda) → ClickHouse, when Postgres event volume demands it.
* Comments, notifications, creator analytics.
* Extract the recommendation service, plus a real-time feature pipeline.

---

## How we work each phase with Claude Code

1. Short plan for the phase, reviewed by you.
2. Implement in small, reviewed commits on a feature branch, one PR per phase or
   sub-phase.
3. Tests and the phase's exit check run in CI or locally before the PR.
4. Docs updated: anything that diverged from these documents gets corrected here.
