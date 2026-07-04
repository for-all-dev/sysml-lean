# Plan (agents)

Ordered execution plan. **Priority: the CI product** (`ci-product.agents.md`);
the paper (`paper.agents.md`) is secondary and mostly falls out of the same
work. Update statuses in place as steps land.

## Done

- [x] Layered core: deep SysML v2 abstract-syntax graph + decidable
      well-formedness (`Sysml/Kernel/*`).
- [x] `sysml` DSL (textual notation §8.2.2 subset) + `#sysml` delaborator.
- [x] View layer (part-level links, reachability), STPA artifact chain with
      totality checks, authority/info-flow split + acyclicity.
- [x] Type-system layer: `WellTyped` judgments + reflection theorems +
      `Decidable` (`Sysml/Typing.lean`).
- [x] Viz (DOT/Mermaid/SVG), markdown report, CLI
      (`list|check|validate|render`), `lake test` driver (23 checks),
      MontiCore second-source oracle.

## Next: CI product track (in order)

1. [x] **Findings engine** (`Sysml/Findings.lean`): structured `Finding`s
   (check id, severity error|warning|info, subject, message) for orphaned
   UCAs, unconstrained hazards, coverage gaps, broken traces, open loops,
   authority cycles, scenario gaps (info). `Analysis.findings`,
   `Analysis.clean`. Stretch still open: prove `clean ↔ wellFormed`
   (spot-checked in Tests.lean for now).
2. [x] **`sysml check [--json]`**: per-example verdicts
   `{name, ok, findings: [...]}`; human output lists findings; exit 1 on
   error findings.
3. [x] **`sysml diff old.json new.json [--markdown]`**: introduced/fixed
   findings (identity = check × subject); exit 1 when errors introduced.
4. [x] **CI workflow**: oracle fetched checksum-pinned (non-fatal on
   network failure — test suite skips gracefully); artifacts job uploads
   verdicts.json + per-example report/SVG.
5. [x] **PR comment bot**: `findings-diff` job — verdicts at base and head
   SHAs, `sysml diff --markdown`, sticky comment via
   `gh pr comment --edit-last --create-if-none`, job fails when errors are
   introduced. UNVERIFIED IN CI: needs a real PR to exercise (gh flags,
   permissions, base-build fallback).
6. [x] **GSN / assurance-case export** (`Sysml/Gsn.lean`,
   `sysml render --format gsn|gsn-svg`): root → losses → hazards →
   constraints/UCA-negations → requirements (rendered *undeveloped* —
   honest: the Lean certificate evidences document structure, not
   requirement satisfaction); scenarios as context nodes; certificate
   status as top-level context. Behavioral evidence attachment is the
   later-sprint follow-up.
7. **LLM-in-the-loop prototype** (after --json): propose UCAs/scenarios,
   reject ill-typed output, feed findings diff back. "Generate, then
   verify."

## Backlog: paper track (secondary)

- Case-study replication (STPA Handbook wheel-brake system — exercises
  hierarchical authority; published UCA tables to check for orphans).
- Formal UCA contexts (Thomas): typed process-model variables; completeness
  as case exhaustiveness. This is also a product feature (better findings).
- Step-4 loss scenarios with causal-factor structure; promote
  `scenariosCover` into `wellFormed`.
- Behavioral LTS semantics linking document typing to model reachability
  (second paper).
- Verso literate paper extraction from `Sysml/Typing.lean`.

## Standing constraints

- Std-only for the library; deps for the CLI only if unavoidable.
- Everything decidable/executable; cite spec sections and
  `stpa-typesystem.pdf` in doc comments.
- No editor/widget dependencies; CLI + files are the product surface.
- DSL keywords non-reserved (`&"…"`); re-run `lake test` after grammar
  changes (oracle + negative suite).
