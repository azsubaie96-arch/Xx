# 05 — Project Structure

> Assumes the recommended stack: Expo/React Native (D1), Python/FastAPI (D2),
> custom web dashboard (D6). Directories are created in the phase where they are
> first needed. Nothing is scaffolded until the decisions are approved.

```
.
├── README.md
├── CLAUDE.md                     # conventions for Claude Code sessions in this repo
├── docs/                         # architecture, schema, plan, decisions (this folder)
├── docker-compose.yml            # Phase 0: postgres:18, redis, minio (local S3)
├── Makefile                      # make dev | test | lint | migrate | gen-client
├── .github/workflows/            # CI: lint, typecheck, tests, migration check
│
├── db/
│   ├── migrations/               # plain, ordered SQL migrations (source of truth)
│   └── seeds/                    # topics, dev fixtures, synthetic users and videos
│
├── apps/
│   ├── api/                      # Python 3.13, FastAPI, modular monolith
│   │   ├── pyproject.toml        # uv-managed; ruff, mypy, pytest
│   │   ├── src/app/
│   │   │   ├── main.py           # FastAPI app factory, router registration
│   │   │   ├── worker.py         # arq worker + scheduled jobs entrypoint
│   │   │   ├── core/             # config, db pool, redis, auth deps, logging, errors
│   │   │   └── modules/
│   │   │       ├── auth/         # each module: api.py · service.py · repo.py · schemas.py
│   │   │       ├── users/
│   │   │       ├── videos/       # + processing/ (provider adapter: mux | self-hosted)
│   │   │       ├── social/
│   │   │       ├── feed/
│   │   │       ├── events/       # ingestion + interaction aggregator job
│   │   │       ├── experiments/
│   │   │       ├── analytics/
│   │   │       └── recommendation/
│   │   │           ├── pipeline.py        # orchestrates the stages below
│   │   │           ├── context.py         # UserContext builder
│   │   │           ├── candidates/        # one file per CandidateSource
│   │   │           ├── filters.py
│   │   │           ├── features/          # registry.py (named, versioned) + builders
│   │   │           ├── rankers/           # base.py (Ranker protocol), heuristic_v1.py, (later) lgbm.py
│   │   │           ├── value_model.py     # Σ w_k · p̂_k
│   │   │           ├── rerank.py          # diversity, creator spacing, exploration slots
│   │   │           ├── cold_start.py      # topic bandit, new-video traffic tiers
│   │   │           └── jobs/              # affinity updater, video stats, trending, tier manager
│   │   └── tests/
│   │       ├── unit/             # ranking logic on fixtures, no I/O
│   │       ├── integration/      # real Postgres + Redis (testcontainers)
│   │       └── replay/           # offline evaluation harness over logged requests
│   │
│   ├── mobile/                   # Expo (React Native, TypeScript)
│   │   ├── app/                  # expo-router screens: (auth)/, (tabs)/feed, upload, profile
│   │   ├── src/
│   │   │   ├── features/feed/    # FeedList, VideoItem, player pool, prefetch
│   │   │   ├── features/upload/
│   │   │   ├── features/auth/
│   │   │   ├── features/profile/
│   │   │   ├── tracking/         # Tracker: view sessions, offline queue, batch flush
│   │   │   ├── api/              # generated client (from packages/api-client)
│   │   │   └── ui/               # shared components, theme
│   │   └── tests/
│   │
│   └── dashboard/                # Phase 4: React + Vite internal analytics app
│
├── packages/
│   └── api-client/               # TypeScript client generated from the API's OpenAPI spec
│
└── ml/                           # Phase 5+: offline training (not deployed with the API)
    ├── datasets/                 # SQL/py to export impressions ⋈ interactions
    ├── training/                 # LightGBM per task, later two-tower / MMoE
    ├── evaluation/               # offline metrics, calibration, reports
    └── notebooks/
```

## Module conventions (API)

* `api.py` — HTTP routes only. Validates input and calls the service.
* `service.py` — business logic. The only thing other modules may import.
* `repo.py` — SQL, through `asyncpg`/SQLAlchemy Core. No ORM magic on the hot
  paths (feed, events).
* `schemas.py` — Pydantic request/response models. These drive OpenAPI and the
  generated TS client.
* The `recommendation` module never imports from `feed`. It takes a
  `UserContext` and returns ranked items, so it can be extracted as a service
  unchanged.
