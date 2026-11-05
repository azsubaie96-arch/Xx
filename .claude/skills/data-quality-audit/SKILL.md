---
name: data-quality-audit
description: Data-quality and fact-check audit of research findings. Use to verify that every number and claim in market, competitor or feasibility work is sourced, current, correctly read, triangulated and internally consistent; to grade each finding A–F; and to list blocking issues before a report is finalised. Use for "check the data", "تحقق من البيانات", "data quality", "fact check".
---

# Data Quality Audit

You are the sceptic. Your job is to find what is wrong, weak or unsupported.
You do not rewrite the analysis; you grade it and list fixes.

## Checks per finding
1. **Source exists** — open the URL. Does the page say what is claimed? Exact figure, unit, year?
2. **Source quality** — tier (T1–T4 per `source-scouting`). Is it a primary source or a reprint of a paid report?
3. **Recency** — figure year vs today. >3 years old = flag; >5 = downgrade unless structural.
4. **Scope match** — same geography, segment, currency, and definition as the claim? (Global number used as Saudi? B2C used as B2B?)
5. **Triangulation** — is there a second independent source? Do they agree within ±30%?
6. **Math** — recompute every derived number. Check unit conversions, currency rates, percentages of percentages, annual vs monthly.
7. **Consistency across agents** — market size vs competitors' combined revenue; SOM vs feasibility revenue plan; pricing in market file vs feasibility file.
8. **Plausibility** — sanity checks (SAM ≤ TAM; SOM share vs comparable companies; customer count ≤ population; CAC realistic for channel).
9. **Labelling** — estimates and assumptions marked as such.

## Grades
- **A** — T1/T2, current, scope-matched, triangulated, math correct.
- **B** — one good source, current, scope-matched.
- **C** — derived or older/weaker source, reasonable and clearly labelled.
- **D** — unverified, T4-only, scope mismatch, or source doesn't fully support it. Report may show only as "unverified".
- **F** — wrong, source contradicts it, math error, or source not found. Must be fixed or removed.

## Blocking issues
Any of: an F on a key number (TAM/SAM/SOM, price, CAC, main competitor funding);
TAM methods differing >3× unexplained; contradictions between agent files; a
key number with only D support.

## Output (`05-quality-audit.md`)
Shared handoff format, ID prefix `Q`. Include:
- Grade table: | Finding ID | File | Grade | Check(s) failed | Note | Fix needed (owner agent) |
- **Blocking issues** list, each assigned to the owning agent with an exact fix.
- Grade distribution and an overall data-quality grade with one-paragraph rationale.
- "What would change the verdict" — the 3 findings the conclusion depends on most and how solid they are.

When re-auditing after fixes, check only the changed findings and update grades.
