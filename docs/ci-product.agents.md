# CI product notes (agents)

Working notes on the product direction: **safety analysis as code** — CI for
safety cases. Companion to `paper.agents.md`.

## Pitch

STPA is increasingly requested in regulated domains (ISO 26262 automotive,
ARP4761 aerospace, FDA infusion pumps — the repo's worked example is
literally an FDA-recall category), but existing tooling (STAMP Workbench,
XSTAMPP, spreadsheets) is desktop-shaped with no CI story. This repo already
has the primitives: model + analysis live in the repository as code; a
checker certifies traceability, coverage, and totality; reports and diagrams
regenerate deterministically.

The product: a PR that changes the control structure or the analysis gets an
automated comment — *these hazards/UCAs are affected; UCA3 is now orphaned;
authority hierarchy still acyclic* — with the regenerated markdown report,
control-structure SVG, and proof-certificate status attached. Orphan errors
fail the build the way type errors do.

## What exists today (the MVP skeleton)

- `lake test` — certificates (`decide` theorems) + negative suite + oracle
  round-trip (skips gracefully without the jar).
- `sysml check` / `sysml validate` — per-example verdicts, exit codes.
- `sysml render --format report|mermaid|svg` — deterministic artifacts.
- GitHub Actions already runs lean-action (build + test).

## Gap list to MVP

1. **CI oracle**: workflow step that fetches `MCSysMLv2.jar`
   (checksum-pinned) so Actions exercises the oracle instead of skipping.
2. **Diff-awareness**: `sysml diff <rev>`? Minimal viable version: run the
   checker on both revisions, diff the *findings* (new/removed orphans,
   coverage gaps, changed hazard trace sets), not the models. The findings
   are already structured — serialize verdicts to JSON, diff JSON.
3. **PR comment bot**: a small workflow posting the findings diff + report
   + SVG as a sticky comment (`gh pr comment --edit-last`).
4. **Assurance-case export**: GSN (Goal Structuring Notation) rendering of
   the artifact chain — losses as top goals, constraints/requirements as
   subgoals, `decide` certificates as solutions. Auditors consume GSN;
   nobody attaches machine-checked evidence to it today.
5. **Machine-readable verdicts**: `sysml check --json` for toolchain
   integration (the JSON schema is basically `WellTyped`'s fields plus
   per-artifact error locations).

## Differentiators to keep sharp

- Proof certificates, not lint warnings: the checker provably decides the
  documented judgments (`Sysml/Typing.lean`).
- Standard grounding: SysML v2 textual notation in, second-source-validated
  notation out — no proprietary model format.
- Editor-independence: everything is CLI/markdown/SVG/mermaid; no
  VS Code/widget dependency anywhere.

## LLM-in-the-loop (later, on-brand for safeguarded AI)

LLM proposes hazards/UCAs/scenarios → checker rejects ill-typed/orphaned
output → human reviews only well-typed candidates. "Generate, then verify."
The type system is what makes LLM assistance defensible in a safety
context; cheap to prototype once `--json` verdicts exist (the LLM gets the
findings diff as feedback).

## Non-goals (for now)

- Behavioral verification (LTS semantics) — research track, see
  `paper.agents.md`.
- Full SysML v2 language coverage — grow the DSL subset by demand.
- Web UI — CLI + CI artifacts are the product surface until there's pull.
