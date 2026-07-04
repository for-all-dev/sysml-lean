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
   authority cycles, scenario gaps. `Analysis.findings`, `Analysis.clean`.
   Stretch DONE (`Sysml/Soundness.lean`): `clean_iff_wellFormed` proves the
   diagnostics and the checker cannot disagree — one lemma per producer,
   plus `docFindings_eq_nil_iff_wellTyped` connecting diagnostics to the
   Prop-level type system. The control-structure checks were restructured
   to *derive from violation lists* (`authorityViolations`,
   `openLoopPairs`), making check/findings agreement definitional there.
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
   introduced. VERIFIED 2026-07-04 on throwaway PR #1: sticky comment with
   the introduced `uca-orphaned UCA4` error posted, findings-diff check
   failed as designed, build job failed independently (lake test catches
   the same regression). PR closed unmerged, branch deleted.
6. [x] **GSN / assurance-case export** (`Sysml/Gsn.lean`,
   `sysml render --format gsn|gsn-svg`): root → losses → hazards →
   constraints/UCA-negations → requirements (rendered *undeveloped* —
   honest: the Lean certificate evidences document structure, not
   requirement satisfaction); scenarios as context nodes; certificate
   status as top-level context. Behavioral evidence attachment is the
   later-sprint follow-up.
7. [~] **LLM-in-the-loop prototype**: `sysml suggest <example> [--llm M]`
   (decided with Quinn 2026-07-04: claude -p CLI invocation; scope =
   scenarios for uca-no-scenario gaps only). Every candidate is gated by
   the checker (real gap UCA, traceability preserved) before display;
   rejected candidates reported as rejected; output is paste-ready Lean.
   IN PROGRESS — implemented, needs a live run against the wheel-brake
   faithful fixture (3 scenario gaps) once fixtures land.

8. **Case-study fixtures** (in flight via subagent): faithful transcription
   of the STPA Handbook wheel-brake tables (expected to pin exactly 17
   findings — the checker quantifying the published example's self-declared
   incompleteness, incl. the Table 2.3 vs 2.5 UCA-2 hazard-trace
   inconsistency we found), plus riffs: a certified-total completion and an
   STPA-Sec extension.

## Backlog: paper track (secondary)

- Case-study replication (STPA Handbook wheel-brake system — exercises
  hierarchical authority; published UCA tables to check for orphans).
- Formal UCA contexts (Thomas): typed process-model variables; completeness
  as case exhaustiveness. This is also a product feature (better findings).
- Step-4 loss scenarios with causal-factor structure (`scenariosCover` —
  existence per UCA — is now enforced in `wellFormed`; structure remains).
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
