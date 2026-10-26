# 03 — Event Tracking Specification

> Status: **PROPOSED**

## 1. Principles

* **The server owns impressions.** Each feed item is created server-side with an
  `impression_id` before it is sent. The client only reports what happened to
  that impression. This ties every watch, skip, and like back to the exact
  ranking decision that produced it.
* **The client reports facts; the server derives meaning.** The client sends
  raw watch time, loop count, and exit reason. "Completed", "fast skip", and
  "replay" are computed server-side from configurable thresholds, so
  definitions can change without an app release and historical data can be
  re-derived.
* **Idempotent and offline-tolerant.** Every event has a client-generated
  UUIDv7 `event_id` and is queued on the device until the server acknowledges
  it. Duplicates are ignored on `(event_id, occurred_at)`.
* **Social actions are double-written.** `POST /videos/{id}/like` changes the
  canonical state (`likes` table). The client *also* sends a `like` event with
  the `impression_id`, so the action is attributed to the impression.

## 2. Transport

`POST /v1/events/batch` — authenticated, at most 100 events per batch, gzip allowed.

```json
{
  "session_id": "0192…",            // app session (foreground period), client-generated
  "app_version": "1.0.0",
  "platform": "ios",
  "events": [
    {
      "event_id": "0192…",
      "type": "view_end",
      "occurred_at": "2026-10-26T21:14:03.120Z",
      "impression_id": "0192…",
      "video_id": "0192…",
      "props": { "watch_ms": 8450, "first_pass_ms": 7200, "loops": 1,
                 "duration_ms": 7200, "exit_reason": "swipe_next" }
    }
  ]
}
```

The server responds `200 {accepted: n, duplicates: m, rejected: [...]}`. It
rejects events with `occurred_at` more than 5 minutes in the future or more
than 7 days in the past, and counts them in a metric.

## 3. Event catalogue (v1)

| Type | When | Props |
|---|---|---|
| `app_open` | App enters foreground. Starts a `session_id`. | `cold_start: bool` |
| `app_close` | App enters background. | `foreground_ms` |
| `view_start` | Video is ≥ 50 % visible and playback starts. | `position` |
| `view_progress` | Every 5 s of playback (heartbeat). Protects data if the app is killed. | `watch_ms`, `loops` |
| `view_end` | Item leaves the screen, or the app backgrounds or quits. | `watch_ms`, `first_pass_ms`, `loops`, `duration_ms`, `exit_reason` (`swipe_next`, `swipe_prev`, `background`, `navigate`, `profile_tap`) |
| `like` / `unlike` | Like toggled. | — |
| `share` | Share sheet completed (not just opened). | `channel` |
| `share_open` | Share sheet opened. | — |
| `follow` / `unfollow` | Follow toggled from a feed item or a profile. | `creator_id`, `surface` |
| `profile_view` | Creator profile opened from a feed item. | `creator_id` |
| `not_interested` | Explicit negative feedback (Phase 3+). | `reason?` |
| `onboarding_topics` | Onboarding finished. | `topic_ids[]` |
| `upload_started` / `upload_completed` | Creator funnel. | `video_id`, `bytes`, `duration_ms` |

## 4. Server-side derivation (`interactions`)

The interaction aggregator folds all events for an impression into one row:

```
watch_ms         = max(view_end.watch_ms, last view_progress.watch_ms)
watch_ratio      = min(first_pass_ms / duration_ms, 1.0)
completed        = first_pass_ms ≥ 0.9 · duration_ms
fast_skip        = exit_reason = 'swipe_next' AND watch_ms < 2000 AND watch_ratio < 0.2
replays          = max(loops − 1, 0)      -- loops counts full passes
liked / shared / followed_creator = matching event with this impression_id
value            = value model (02-recommendation-engine.md §3), stored with value_model_version
```

An interaction is **finalised** 30 minutes after its last event. It is upserted
earlier, so the affinity updater can react within seconds.
