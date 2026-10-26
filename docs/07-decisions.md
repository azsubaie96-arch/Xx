# 07 — Decisions Requiring Your Approval

Each decision lists a recommendation and the alternatives. The **Blocks** column
shows which phase can't start until it's answered. Reply with, for example,
"approve all", or "D3: self-hosted, D6: Metabase".

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| D1 | Mobile framework | Expo (React Native, TypeScript) | Phase 0 |
| D2 | Backend language and shape | Python + FastAPI modular monolith | Phase 0 |
| D3 | Video processing and hosting | Managed (Mux or Cloudflare Stream) for the MVP | Phase 1 |
| D4 | Authentication | In-house (email + password, JWT) behind an interface; add Apple and Google sign-in before App Store launch | Phase 1 |
| D5 | Event storage | Postgres (partitioned) for the MVP; move to a streaming pipeline and ClickHouse when volume requires | Phase 2 |
| D6 | Analytics dashboard | Custom internal web app on a SQL metric layer | Phase 4 |
| D7 | Cloud and hosting | Decide at the end of Phase 1; local Docker until then | Phase 1 end |
| D8 | Ranking objective (value-model weights) | Weight deliberate actions above passive watch time (see below) | Phase 3 |
| D9 | Moderation, age gating, privacy | Required before any public launch; not before internal MVP testing | Public launch |
| D10 | MVP scope exclusions | No comments, DMs, music library, editing, or live in MVP | Now |
| D11 | Onboarding topic picker | Yes, skippable | Phase 3 |

---

### D1 — Mobile framework: **Expo / React Native** (recommended)

* **Why:** one TypeScript codebase for iOS and Android. `expo-video` handles
  HLS playback and preloading well enough for a vertical feed. Over-the-air
  updates let us iterate on the tracker and UI without store review. Types can
  be shared with the generated API client.
* **Alternatives:**
  * *Flutter* — comparable performance, but Dart and a weaker codegen story with
    our API.
  * *Native Swift + Kotlin* — best scroll and playback performance and full
    player control, but roughly twice the effort.
* **Risk:** if playback smoothness falls short on low-end Android, the
  feed screen alone can drop to a native module without rewriting the app.

### D2 — Backend: **Python + FastAPI modular monolith** (recommended)

* **Why:** the competitive advantage is the recommender, and its future is
  Python (LightGBM, PyTorch, pandas). One language for API, ranking, and ML
  means the heuristic ranker and the learned ranker share the same feature code,
  which is the main defence against training/serving skew. A monolith keeps
  operations trivial while small.
* **Alternative:** *TypeScript (NestJS/Fastify) API + Python recommendation
  service* — same language as mobile, but two services, a network hop on the
  hot path, and duplicated feature logic from day one.

### D3 — Video processing and hosting: **managed for MVP** (recommended)

* **Why:** transcoding to an adaptive HLS ladder, thumbnails, and CDN delivery
  are a large, solved problem. A managed provider (Mux or Cloudflare Stream)
  gives direct uploads, webhooks, and global playback in days rather than weeks.
* **Cost:** usage-based (minutes encoded, stored, and delivered). It is cheap
  at MVP scale and becomes a top cost line at scale. The `videos/processing`
  adapter keeps a later move to self-hosted possible.
* **Alternative:** *self-hosted* FFmpeg workers + S3/R2 + CDN. Cheaper per
  minute at scale, but we own the encoding ladder, retries, and CDN config.
* **Need from you:** provider preference, and whether you already have
  accounts or credits with AWS, GCP, Cloudflare, or Mux.

### D4 — Authentication: **in-house, behind an interface** (recommended)

* **Why:** email + password with Argon2id and rotating refresh tokens is a small
  amount of well-understood code. It has no per-user vendor cost and runs fully
  locally in tests.
* **Note:** Apple requires Sign in with Apple if the app offers other
  third-party logins. Plan both Apple and Google sign-in before store submission.
* **Alternative:** *managed* (Firebase Auth, Supabase Auth, Clerk). This
  outsources password security and social login, but adds a vendor dependency
  and per-MAU pricing on some providers.

### D5 — Event storage: **Postgres first** (recommended)

* **Why:** monthly partitions comfortably hold tens of millions of events per
  month. It's one system to run, and the joins between impressions and outcomes
  are plain SQL. The ingestion module is the only writer, so swapping to
  Redpanda → ClickHouse later is localised.
* **Alternative:** Kafka/Redpanda + ClickHouse from day one. Built for scale,
  but large operational overhead before we have users.

### D6 — Analytics dashboard: **custom internal web app** (recommended)

* **Why:** recommendation-quality views (by ranker version, variant, candidate
  source, and traffic tier) and experiment readouts are product-specific. The
  same app can later host moderation tooling.
* **Alternative:** *Metabase or Superset* over the same SQL views. Faster to
  start and good for ad-hoc exploration. Because the metric layer is SQL views,
  we can also run Metabase alongside for ad-hoc questions.

### D7 — Cloud and hosting: **decide after Phase 1**

Options range from simple PaaS (Fly.io, Render, Railway) to AWS or GCP. They
matter for cost and region, so tell me if you have a preferred provider, credits,
or a target market/region. Data-residency rules can force this choice.

### D8 — Ranking objective: **reward deliberate engagement** (product decision)

This is the most important product decision. It defines what the algorithm
optimises for. Proposed defaults (all tunable per experiment variant):

| Signal | Weight | Rationale |
|---|---|---|
| Completion | 1.0 | Core relevance signal for short video |
| Watch ratio | 0.5 | Partial credit for long videos |
| Replay (≤ 3) | 0.4 | Strong interest; capped to avoid rewarding loop-bait |
| Like | 2.0 | Explicit approval |
| Share | 3.0 | Strongest public endorsement |
| Follow | 4.0 | Long-term relationship; best predictor of retention |
| Fast skip | −1.5 | Implicit "not for me" |

Pure watch-time optimisation maximises short-term minutes but tends to drift
toward sensational content and hurts long-term trust. These weights lean toward
satisfaction and retention. **Please confirm, or tell me your priority** (for
example, maximise time spent, or creator growth).

### D9 — Trust, safety and legal: **required before public launch**

Not needed for an internal MVP, but these have to be designed in before real
users upload content:

* **Moderation:** automated scanning of uploads (nudity and violence
  classifiers; known-CSAM hash matching, which carries legal reporting duties in
  many jurisdictions), a report flow, and a review queue.
* **Age gating:** minimum age (13+ in most markets), with different defaults
  for minors.
* **Privacy:** behavioural tracking must be disclosed. Users need data export
  and deletion (GDPR/CCPA). Consent requirements vary by region.
* **App Store and Play policies** for user-generated content: blocking,
  reporting, and terms acceptance.

Please tell me your **launch markets**. They determine which of these apply.

### D10 — MVP scope exclusions

The MVP excludes comments, DMs, a music or sound library (licensing is a
significant legal and cost item), in-app editing and filters, live streaming,
and monetisation. Comments are the first candidate after the MVP.

### D11 — Onboarding topic picker: **yes, skippable**

Asking for 3+ topics on first launch roughly halves the cold-start exploration
needed. It is skippable, since forced onboarding loses some users. Its effect
on D1 retention will be measured on the dashboard.
