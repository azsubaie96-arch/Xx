# Short-Video App (working title)

A TikTok-style vertical short-video app. Its competitive advantage is a
**personalised recommendation engine that learns from each user's behaviour**.

**Status:** design phase. No application code yet. The architecture and plan
are awaiting approval of the decisions in [docs/07-decisions.md](docs/07-decisions.md).

## Documents

| Doc | Contents |
|---|---|
| [01 — Architecture](docs/01-architecture.md) | System components, data stores, request flows, scaling path |
| [02 — Recommendation engine](docs/02-recommendation-engine.md) | Ranking pipeline, heuristic ranker, personalisation, cold start, ML evolution |
| [03 — Event tracking](docs/03-event-tracking.md) | Client event catalogue, ingestion contract, label derivation |
| [04 — Database schema](docs/04-database-schema.md) | Schema overview; DDL in [`db/migrations/0001_init.sql`](db/migrations/0001_init.sql) |
| [05 — Project structure](docs/05-project-structure.md) | Monorepo layout and module conventions |
| [06 — Implementation plan](docs/06-implementation-plan.md) | Phases 0–6 with exit checks |
| [07 — Decisions](docs/07-decisions.md) | Choices that need owner approval |

## Proposed stack (pending approval)

Expo / React Native · Python 3.13 + FastAPI · PostgreSQL 18 · Redis ·
managed video processing (Mux or Cloudflare Stream) · React/Vite analytics dashboard
