---
name: source-scouting
description: Research-source discovery for market and startup studies. Use to find, rank and record the most reliable sources (official statistics, regulators, industry reports, funding databases, company filings, app stores, forums) for a given idea and geography, and to hand other agents a source registry. Also usable alone when the user asks "where can I find data on X".
---

# Source Scouting

Goal: give the other agents the **best available evidence base** in the least
time, so they don't each search blindly.

## Method
1. **Read the brief.** List the data needs: market size, growth, customer counts,
   spend per customer, competitors, funding, prices, regulation, behaviour.
2. **Map needs to source types** using `references/source-catalog.md`. Always cover:
   official statistics → regulator → industry/consulting reports → funding
   databases → company sites/filings → customer voice (reviews, app stores, forums, social).
3. **Search wide, then narrow.** Run several searches in parallel per need, in
   English **and** the local language (Arabic for GCC). Try the official source
   site directly, not only search results.
4. **Open and check** each candidate: does it actually contain the data? What date?
   Who published it? Is it free, paywalled, or a press-release summary of a paid report?
5. **Tier each source:**
   - **T1** — official statistics, regulators, central banks, audited filings, peer-reviewed.
   - **T2** — reputable research firms, multilateral bodies (World Bank, IMF, OECD), major press quoting primary data.
   - **T3** — trade press, company blogs, funding databases, credible industry associations.
   - **T4** — SEO "market report" sites, forums, social posts, unsourced articles. Use for signals only, never as the only source of a key number.
6. **Note paywalled reports** that matter: title, publisher, price if visible, and the free summary figures.

## Output (`01-sources.md`)
Follow the shared handoff format. The main table is the **registry**:

| ID | Title | Publisher | Date | URL | Tier | Covers (needs) | Key figures seen | Access |

Then: **Coverage matrix** (needs × best source IDs), **Gaps** (needs with no
T1/T2 source and suggested proxy), and **Search log** (queries that worked).

Aim for 15–30 sources on `standard`, 30–50 on `deep`, 8–12 on `quick`.
Never list a URL you did not open.
