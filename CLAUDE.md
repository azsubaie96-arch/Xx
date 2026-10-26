# CLAUDE.md

Short-video app with a personalised recommendation engine. Read `docs/` before
changing architecture. `docs/06-implementation-plan.md` says which phase we're in.

## Ground rules

- Build one phase at a time, and stop at each phase's exit check for owner review.
- Don't change decisions in `docs/07-decisions.md` without asking. If code needs
  to diverge from a doc, update the doc in the same PR.
- Schema changes go in a new numbered file in `db/migrations/`. Never edit an
  applied migration.
- Every feed item must be logged as an impression (ranker version, features,
  predictions, propensity). Never bypass this. It is the training data.
- Rankers implement the `Ranker` protocol and return per-task predictions. The
  final score is computed only in `value_model.py`.
- `recommendation` must not import from `feed` or any HTTP code.
- Thresholds (completion, fast skip, decay constants, weights) live in config,
  not inline literals.

## Commands

_To be filled in during Phase 0._
