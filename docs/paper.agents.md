# Paper notes (agents)

Working notes toward the research artifact. Companion docs:
`stpa-typesystem.pdf` (the type system this repo mechanizes) and
`stpa-litreview.pdf` (positioning: nobody frames orphaned UCAs as
non-exhaustiveness errors or the artifact chain as typing judgments).

## Thesis

A mechanized, decidable type system for STPA analysis documents, grounded in
the SysML v2 standard (OMG formal/2026-03-02), with a running checker that
provably decides the paper's judgments (reflection theorems), an emitter
validated against an independent second-source parser, and machine-checked
case studies.

## Contribution inventory (implemented ↔ paper section)

| Paper concept | Code | Status |
|---|---|---|
| Artifact chain: losses ← hazards ← {constraints, UCAs} ← requirements ← scenarios | `Sysml/Stpa.lean` (`Loss`, `Hazard`, `SystemConstraint`, `Uca`, `Requirement`, `Scenario`) | done |
| Orphaned UCA = non-exhaustiveness error (central totality judgment) | `UcaRefined`, `Analysis.ucasRefined` | done |
| Hazard totality (every hazard constrained) | `HazardConstrained`, `Analysis.hazardsConstrained` | done |
| Authority relation acyclic (DAG), separate from information flow (cyclic) | `ControlStructure.authorityEdges` / `authorityAcyclic`; reachability never over the union | done |
| Coverage: control action × guide phrase → UCA or justified N/A | `Considered`, `Analysis.ucasCover` | done |
| Referential well-kindedness of every artifact | `HazardOk`, `ConstraintOk`, `UcaOk`, `RequirementOk`, `ScenarioOk` | done |
| Typing rules ↔ checker correspondence | `Sysml/Typing.lean`: `WellTyped` (Prop) + reflection theorems (`wellTyped_iff` etc.) + `Decidable` instance | done |
| Closed control loops (coverage over fb, per relation) | `controlLoopsClosed` | done |
| SysML v2 grounding: deep abstract-syntax graph + textual-notation DSL + delaborator | `Sysml/Kernel/*`, `Sysml/Dsl.lean` | done (subset) |
| Emitter validity via second-source oracle (MontiCore) | `Sysml/Oracle.lean`, `sysml validate`, `lake test` | done |
| Loss scenarios with causal-factor structure (step 4 proper) | `Scenario` is desc-only; `scenariosCover` optional judgment | LATER SPRINT |
| Formal UCA contexts (Thomas): predicates over process-model variables; completeness = case exhaustiveness | `Uca.context : String` today | NEXT BIG BET |
| Behavioral semantics (LTS) linking document typing to model reachability | none | SECOND PAPER |

## Evaluation plan

1. Replicate 1–2 published STPA case studies in the DSL — canonical: STPA
   Handbook aircraft wheel-brake system (has published UCA tables to check
   against); alternatives: automotive AEB, published insulin-pump STPA.
2. Run the checker; report every orphan/coverage/traceability error found in
   the published tables. A totality error in a published analysis is the
   headline evaluation result.
3. Compare against STAMP Workbench / XSTAMPP: what do they check (kinds,
   syntax) vs what this checks (totality, coverage, acyclicity), plus the
   proof-certificate angle none of them have.

## Venue candidates

SAFECOMP, NASA Formal Methods (NFM), STAMP Workshop (friendly audience,
feedback round), MEMOCODE/FMICS as backups. Journal option: Journal of
Systems and Software or Safety Science for the extended version.

## Writing infrastructure

Verso (Lean's literate/documentation framework) for a paper whose typing
rules are extracted from `Sysml/Typing.lean` — the rules in the paper *are*
the mechanization. Alternatively latex with lean4 listings; decide when
drafting starts.

## Positioning sentences (draft)

- "We give the first mechanized type system for STPA documents: an orphaned
  unsafe control action is a non-exhaustiveness error, checked by `decide`."
- "The checker is not merely inspired by the rules — it provably decides
  them (`wellTyped_iff`), so paper and tool cannot drift."
- "Analyses are grounded in SysML v2: models are written in (a subset of)
  the standard textual notation inside Lean, and the emitter round-trips
  through an independent second-source parser."
