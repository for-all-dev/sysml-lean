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
7. [x] **LLM-in-the-loop prototype**: `sysml suggest <example> [--llm M]`
   (decided with Quinn 2026-07-04: claude -p CLI invocation; scope =
   scenarios for uca-no-scenario gaps only). Every candidate is gated by
   the checker before display; rejected candidates reported; output is
   paste-ready Lean. VERIFIED LIVE 2026-07-04 against the wheel-brake
   faithful fixture: 3/3 gaps closed with plausible, control-structure-
   grounded causal scenarios, all validated, exit 0.

8. [x] **Case-study fixtures** (via subagent): faithful wheel-brake
   transcription pinning exactly 17 findings (the checker quantifying the
   handbook's self-declared incompleteness, incl. the Table 2.3 vs 2.5
   UCA-2 trace inconsistency), plus riffs: certified-total completion and
   STPA-Sec extension. 34 tests, oracle round-trips on all three models.

9. [~] **GitHub Marketplace action** (in flight via subagent): TypeScript
   action at repo root (action.yml + action/dist), wrapping check → base/
   head diff → sticky comment → fail-on-regression, with elan bootstrap
   and optional checksum-pinned oracle fetch.

10. [x] **Interop research** (docs/interop.agents.md): Astah System Safety
    round-trips XMI 2.5 + SACM and platforms IPA's STAMP Workbench; SACM
    accepted by both Astah and Adelard ASCE; ranked build order: .sysml
    import > SACM export > ReqIF > API client > CSV.

11. [~] **SACM export** (in flight via subagent, decided with Quinn
    2026-07-04): Sysml/Sacm.lean — Analysis → SACM 2.2 XMI mirroring the
    GSN argument structure (Claims / AssertedInference / AssertedContext /
    ArtifactReference, requirements toBeSupported), `sysml render --format
    sacm`. Follow-up: actually import the output into Astah/ASCE to verify
    schema conformance (unverified until then).

12. **NEXT SESSION: .sysml file import / parser sprint.** Spec agreed with
    Quinn (subagents, straight on master): `Sysml/Parser.lean` — runtime
    tokenizer + two-pass recursive-descent parser for the textual-notation
    subset (mirror Sysml/Dsl.lean's walk/resolution semantics: collect
    elements with sequential ids, then resolve typings and connector ends,
    so forward references work); tolerate `//` and `/* */` comments and
    flexible whitespace; `String → Except String Model`. Tests: parse ∘
    render round-trip over every registry model (compare rendered
    normal forms to dodge id-assignment differences), negative parse
    cases. CLI: `sysml check <path>.sysml` and `sysml render <path>.sysml
    --format …` — args ending in .sysml parse the file as a bare model
    (model-level findings only). This is the front door for models
    exported from Cameo/Syside/SysON, and starts the long-planned checker
    sprint.

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
