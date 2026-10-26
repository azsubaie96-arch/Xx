# 02 — Recommendation Engine

> Status: **PROPOSED**. The objective weights in §3 are a product decision (D8).

## 1. Design principle: build the ML system now, with hand-written models

The MVP ranker is a heuristic. Everything around it already has the shape of a
production ML recommender:

```
           ┌──────────────┐   ┌────────┐   ┌──────────┐   ┌────────┐   ┌──────────┐   ┌─────────┐
request ──▶│  candidate   │──▶│ filter │──▶│ features │──▶│ ranker │──▶│ re-rank  │──▶│ logging │──▶ response
           │  generation  │   └────────┘   └──────────┘   └────────┘   └──────────┘   └─────────┘
           │ (N sources)  │                                   ▲
           └──────────────┘                         chosen by experiments
```

Later, the ML model replaces only the **ranker** box, and later still adds an
embedding-based **candidate source**. The surrounding stages and the logging do
not change. Training data accumulates from day one.

### Core interfaces (Python, illustrative)

```python
@dataclass(frozen=True)
class UserContext:
    user_id: UUID
    is_new: bool                    # < N meaningful interactions
    locale: str
    country: str | None
    local_hour: int
    session_depth: int              # items already served this session
    affinities: AffinityProfile     # decayed topic / hashtag / creator scores
    following: frozenset[UUID]

@dataclass
class Candidate:
    video_id: UUID
    source: str                     # "trending" | "affinity_topic" | "following" | "exploration" | ...
    source_score: float

class CandidateSource(Protocol):
    name: str
    async def fetch(self, user: UserContext, limit: int) -> list[Candidate]: ...

class FeatureBuilder(Protocol):
    version: str
    async def build(self, user: UserContext, cands: list[Candidate]) -> FeatureMatrix: ...

class Ranker(Protocol):
    version: str                    # e.g. "heuristic_v1", "lgbm_2027_01_15"
    def predict(self, features: FeatureMatrix) -> Predictions: ...   # per-task probabilities
    # The final score is Σ w_task · p_task, applied by a shared Scorer.

class ReRanker(Protocol):
    def rerank(self, user: UserContext, scored: list[ScoredCandidate], n: int) -> list[ScoredCandidate]: ...
```

**Key choice:** the ranker returns **per-task predictions** (P(complete),
P(like), P(share), P(follow), E[watch ratio], P(skip)), not one opaque score.
A single, configurable **value model** turns these into the final score.

* The heuristic ranker estimates each probability from smoothed statistics.
* The ML ranker learns each one (multi-task).
* Changing what the product optimises for means changing weights, not retraining.

## 2. Signals → labels

Raw client events are aggregated into one `interactions` row **per impression**
(see [03-event-tracking.md](03-event-tracking.md)):

| Signal | Definition (MVP defaults, configurable) |
|---|---|
| `watch_ms` | Total foreground playback time for this impression. Includes loops. |
| `watch_ratio` | `min(first_pass_watch_ms / duration_ms, 1.0)` |
| `completed` | First pass reached ≥ 90 % of the duration. |
| `fast_skip` | Swiped away after < 2 s **and** < 20 % of the duration. |
| `replays` | Number of extra loops past the first full pass. Capped at 3 for scoring. |
| `liked` / `shared` / `followed_creator` | The action happened during this impression. |

These are both the **features of the past** (aggregated into stats and
affinities) and the **labels of the future** (ML training targets).

## 3. Value model (what "good" means) — D8

Per-impression engagement value:

```
value = 1.0 · completed
      + 0.5 · watch_ratio
      + 0.4 · min(replays, 3)
      + 2.0 · liked
      + 3.0 · shared
      + 4.0 · followed_creator
      − 1.5 · fast_skip
```

The final ranking score uses the same weights over **predicted** probabilities:

```
score(u, v) = Σ_k  w_k · p̂_k(u, v)
```

Proposed default weights: completion 1.0, watch ratio 0.5, replay 0.4, like 2.0,
share 3.0, follow 4.0, skip −1.5. They favour **deliberate** signals (share,
follow) over passive watch time. That reduces "doom-scroll" optimisation and
rewards content people actually value. **These numbers need your sign-off (D8).**

## 4. Heuristic ranker `heuristic_v1`

### 4.1 Video quality priors (global)

For each video and task `k`, compute a smoothed, time-decayed rate (Bayesian
average). This stops a video with 3/3 completions from outranking one with 900/1000:

```
rate_k(v) = (events_k(v) + α · prior_k) / (impressions(v) + α)
```

* `prior_k` is the platform-wide mean rate for task `k`, per topic when the
  topic has enough data. `α` = 50 impressions.
* Counts are kept for all time and over a 72 h window. The score blends them:
  `0.7 · rate_72h + 0.3 · rate_all`.

### 4.2 Personal lift

Each user has decayed affinity scores over **topics**, **hashtags**, and
**creators**. Each interaction adds its `value` (§3) to the entities attached to
the video. Decay is applied lazily on read:

```
affinity(u, e) ← affinity(u, e) · exp(−Δt / τ) + value       τ = 7 days (topics/hashtags), 14 days (creators)
```

The scores are normalised per user into `[−1, 1]` with `tanh(a / scale_u)`.
Here `scale_u` is the user's median absolute affinity, which makes heavy and
light users comparable.

```
lift(u, v) = 1 + β_t · mean_topic_affinity(u, v)
               + β_h · max_hashtag_affinity(u, v)
               + β_c · creator_affinity(u, v)
               + β_f · is_following(u, creator(v))
p̂_k(u, v) = clamp(rate_k(v) · lift(u, v), 0, 1)        (for fast_skip, divide by lift instead)
```

Initial values: `β_t = 0.6`, `β_h = 0.3`, `β_c = 0.8`, `β_f = 0.5`. Negative
affinity, built from fast skips, pushes the lift below 1. This is how "not
interested" is learned implicitly.

### 4.3 Freshness

`score ← score · (0.85 + 0.15 · exp(−age_hours / 48))`. This is a mild boost so
the feed feels alive without burying proven content.

## 5. Candidate generation (≈ 500 candidates per request)

| Source | What | Share of pool | Store |
|---|---|---|---|
| `affinity_topic` | Top-quality recent videos in the user's top-5 topics. | 35 % | Redis sorted set per topic |
| `affinity_creator` | Recent videos from creators with high affinity whom the user doesn't follow. | 10 % | Postgres |
| `following` | Recent videos from followed creators. | 15 % | Postgres |
| `trending` | Global and locale trending (quality × recency). | 25 % | Redis sorted set |
| `exploration` | New videos in the cold-start pool (§7). | 15 % | Redis sorted set per tier |

Later: `embedding_ann` (two-tower retrieval) and `similar_to_recent_likes`.

**Filters:** already served this session, already watched (completed or skipped)
in the last 30 days, the user's own videos, blocked creators, and videos not in
`ready`/public state.

## 6. Re-ranking

These rules apply after scoring and before returning the page:

1. **Creator spacing:** no two videos from the same creator within 4 positions.
2. **Topic diversity:** at most 3 of any 10 consecutive items share a primary topic.
3. **Exploration slots:** positions 3 and 8 of each page of 10 are reserved for
   exploration. That gives about 20 % for new users and about 10 % for
   established users. These items are picked by Thompson sampling over topics
   (§7.1) or from the new-video pool (§7.2).
4. **Propensity logging:** for every impression, log whether it came from an
   exploration slot and its selection probability. Future ML training uses this
   to correct position and selection bias.

## 7. Cold start

### 7.1 New users

A user counts as "new" until they have ≥ 30 interactions that aren't skips.

1. **Onboarding (optional, skippable, D11):** pick 3 or more topics from about
   20. Each pick seeds that topic's affinity with a modest prior (+2.0), which
   is enough to steer early candidates while real behaviour overrides it within
   a few swipes.
2. **Context prior:** device locale or country selects the locale-specific
   trending pool.
3. **Topic bandit:** each topic has a Beta(α, β) posterior on "this user
   engages", where success means `completed ∨ liked ∨ shared`. Sampling from it
   picks the topics to fill. This explores broadly at first and converges fast.
   Posteriors start from the global topic popularity.
4. **Fast feedback:** affinities update within seconds of each batch flush, and
   `GET /feed` returns pages of 10, so the next page already reflects the
   current session.
5. **Higher-quality bar:** new users mostly see the top of the trending
   distribution. First impressions drive D1 retention, which the dashboard
   tracks specifically for this cohort.

### 7.2 New videos (creator cold start)

Every new video gets guaranteed, measured exposure through **traffic tiers**:

| Tier | Impressions budget | Promote if | Otherwise |
|---|---|---|---|
| T0 | 200 | Smoothed value per impression ≥ topic median | Stays in topic and following feeds only |
| T1 | 2 000 | ≥ 60th percentile of its topic | Demote to normal ranking |
| T2 | 20 000 | ≥ 75th percentile | Demote to normal ranking |
| Graduated | — | Competes in `trending` and `affinity_topic` | — |

Exploration impressions go preferentially to users whose topic affinity matches
the video's topics, so new videos get a fair test audience.

## 8. Evolution path to machine learning

| Stage | Ranker | Retrieval | Prerequisites |
|---|---|---|---|
| **v1 (MVP)** | `heuristic_v1` — smoothed rates × affinity lift | Rule-based sources | Logging of impressions and features |
| **v2** | Gradient-boosted trees (LightGBM), one model per task, trained daily on `impressions ⋈ interactions`, served in-process | Same | ~1M labelled impressions; offline eval harness; A/B framework |
| **v3** | Learned value-model weights; calibration; position-bias correction using logged propensities | Two-tower embedding retrieval (pgvector HNSW); content embeddings from frames, audio, and caption for cold start | Training pipeline in `ml/`, embedding jobs, GPU for content embeddings |
| **v4** | Multi-task deep ranker (MMoE) with sequence features (last N interactions) | Real-time user embeddings | Streaming features (Kafka → feature store), inference service |

**What keeps this path open, built in the MVP:**

* **Feature logging at serve time.** The exact feature vector the ranker saw is
  stored with each impression (`impressions.features`). Training uses these
  logged values, so there is no training/serving skew.
* **Versioned features.** `FeatureBuilder.version` is logged, and features are
  defined in one registry module with names, types, and default values.
* **Ranker version and experiment variant on every impression,** so any two
  rankers can be compared offline and online.
* **Per-task predictions plus a separate value model** (§1), so the
  heuristic→ML swap changes only where the probabilities come from.
* **A replay harness** that re-scores logged requests with any ranker to
  compute offline metrics (NDCG@10, AUC per task, calibration) before an A/B test.

## 9. Measuring recommendation quality

The analytics dashboard reports these per ranker version, experiment variant,
candidate source, and user cohort (new vs established):

* **Engagement per impression:** mean `value`, completion rate, mean watch
  ratio, fast-skip rate, like, share, and follow rates.
* **Session:** items per session, session length, session-ending skip rate.
* **Retention (the north-star guardrail):** D1, D7, and D30 by cohort and by
  the variant assigned at sign-up.
* **Ecosystem health:** catalogue coverage (% of ready videos shown in 7 days),
  creator exposure Gini, new-video graduation rate, topic diversity per session.
