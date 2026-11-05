# Handoff format (all agents)

Every agent writes its **full** output to its assigned file and returns to the
master agent **only** a summary of ≤ 200 words plus the file path.

## File structure

```markdown
# <Agent name> — <idea slug>
_Date: YYYY-MM-DD · Market: <geo> · Depth: <quick|standard|deep>_

## Summary
3–6 bullets. The answers to the questions you were assigned.

## Findings
| ID | Claim / metric | Value | Unit & year | Source(s) | Type | Confidence |
|----|----------------|-------|-------------|-----------|------|------------|
| M1 | Saudi online grocery GMV | 9–11 | SAR bn, 2025 | S3, S7 | reported | high |
| M2 | Share of households ordering weekly | 18% | %, 2026 | estimate from S4 + S9 | derived | medium |

- **ID prefix:** S = source, M = market, C = competitor, F = feasibility, Q = quality, X = extra agent.
- **Type:** `reported` (stated directly by the source) · `derived` (your calculation from sourced inputs — show the formula in Notes) · `assumption` (no source; explain why it is reasonable).
- **Confidence:** `high` (≥2 independent good sources agree) · `medium` (one good source, or derived from good inputs) · `low` (weak/old source, or assumption).

## Analysis
Narrative, tables, calculations. Show formulas for anything derived.

## Gaps & open questions
What you could not find or verify, and how it could be found (survey, interview, paid report).

## Sources used
| ID | Title | Publisher | Date | URL | Tier |
```

## Rules
- Never invent a source, URL, number or quote. If you could not find it, say so.
- Quote the exact figure and page/section when possible.
- Convert currencies at a stated rate and year; keep the original in brackets.
- Separate the market you can measure from the market you are guessing.
