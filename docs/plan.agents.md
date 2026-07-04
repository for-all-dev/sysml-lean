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

1. **Findings engine** (`Sysml/Findings.lean`): turn Bool failures into
   structured `Finding`s (check id, severity error|warning|info, subject,
   message) — orphaned UCAs, unconstrained hazards, uncovered
   (path × guide-phrase) pairs, broken traces, open loops, authority
   cycles, scenario gaps (info until step-4 sprint). `Analysis.findings`.
   Stretch (paper-adjacent): prove `findings = [] ↔ docWellFormed`.
2. **`sysml check [--json]`**: machine-readable verdicts — per example:
   `{name, ok, findings: [...]}`. Human output keeps ✓/✗ but lists findings.
3. **`sysml diff old.json new.json [--markdown]`**: classify findings as
   introduced/fixed/unchanged between two verdict files; markdown output
   shaped for a PR comment.
4. **CI workflow**: extend GitHub Actions — fetch `MCSysMLv2.jar`
   (checksum-pinned) so the oracle runs in CI; `lake test`; emit
   report/SVG/verdicts as build artifacts.
5. **PR comment bot**: on pull_request, run verdicts on base and head,
   `sysml diff`, post sticky comment (`gh pr comment`) with findings diff +
   report + control-structure diagram.
6. **GSN / assurance-case export**: artifact chain as Goal Structuring
   Notation (losses → constraints/requirements as goal tree, `decide`
   certificates as solutions); SVG via existing dot pipeline.
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
