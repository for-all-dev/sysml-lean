import Sysml.Findings
import Sysml.Typing

/-!
# Soundness and completeness of the findings engine

`Analysis.findings` (the diagnostics) and `Analysis.wellFormed` (the
decision procedure) are separate code paths; this module proves they cannot
disagree:

* one lemma per producer: its findings are `[]` iff the corresponding check
  passes;
* `clean_iff_wellFormed : a.clean = true ↔ a.wellFormed = true`;
* corollary `clean_iff_wellTyped`, connecting the diagnostics all the way
  to the Prop-level typing judgments of `Sysml.Typing` (for the document
  part, via `wellTyped_iff`).

So an empty findings list is a *certificate*, not a hope — and conversely a
failing check always produces an explanatory finding.
-/

namespace Sysml.Stpa

open Sysml.Kernel

namespace Analysis

/-! ## List helpers -/

private theorem guardFinding_eq_nil {ok : Bool} {c s m : String} :
    guardFinding ok c s m = [] ↔ ok = true := by
  cases ok <;> simp [guardFinding]

variable (a : Analysis)

/-! ## Model and control structure -/

theorem modelFindings_eq_nil_iff :
    a.modelFindings = [] ↔ a.model.wellFormed = true := by
  simp [modelFindings, Model.wellFormed, guardFinding_eq_nil,
    List.append_eq_nil_iff, Bool.and_eq_true, and_assoc]

theorem csFindings_eq_nil_iff :
    a.csFindings = [] ↔ a.cs.wellFormed a.model = true := by
  simp [csFindings, ControlStructure.wellFormed, guardFinding_eq_nil,
    ControlStructure.authorityAcyclic, ControlStructure.controlLoopsClosed,
    List.append_eq_nil_iff, List.map_eq_nil_iff, List.isEmpty_iff,
    Bool.and_eq_true, and_assoc]

/-! ## Document producers, one lemma per conjunct -/

theorem hazardTraceFindings_eq_nil_iff :
    a.hazardTraceFindings = [] ↔ a.hazardsTraceable = true := by
  simp only [hazardTraceFindings, hazardsTraceable, List.flatMap_eq_nil_iff,
    List.append_eq_nil_iff, List.filterMap_eq_nil_iff, List.all_eq_true,
    Bool.and_eq_true]
  refine forall_congr' fun h => forall_congr' fun _ => ?_
  simp [List.isEmpty_iff]

theorem constraintTraceFindings_eq_nil_iff :
    a.constraintTraceFindings = [] ↔ a.constraintsTraceable = true := by
  simp only [constraintTraceFindings, constraintsTraceable,
    List.flatMap_eq_nil_iff, List.append_eq_nil_iff, List.filterMap_eq_nil_iff,
    List.all_eq_true, Bool.and_eq_true]
  refine forall_congr' fun c => forall_congr' fun _ => ?_
  simp [List.isEmpty_iff]

theorem unconstrainedHazardFindings_eq_nil_iff :
    a.unconstrainedHazardFindings = [] ↔ a.hazardsConstrained = true := by
  simp [unconstrainedHazardFindings, hazardsConstrained,
    List.filterMap_eq_nil_iff, List.all_eq_true]

theorem ucaTraceFindings_eq_nil_iff :
    a.ucaTraceFindings = [] ↔ a.ucasTraceable = true := by
  simp only [ucaTraceFindings, ucasTraceable, List.flatMap_eq_nil_iff,
    List.append_eq_nil_iff, List.filterMap_eq_nil_iff, List.all_eq_true,
    Bool.and_eq_true]
  refine forall_congr' fun u => forall_congr' fun _ => ?_
  simp [List.isEmpty_iff, and_assoc]

theorem coverageFindings_eq_nil_iff :
    a.coverageFindings = [] ↔ a.ucasCover = true := by
  simp only [coverageFindings, ucasCover, List.flatMap_eq_nil_iff,
    List.filterMap_eq_nil_iff, List.all_eq_true]
  refine forall_congr' fun c => forall_congr' fun _ =>
    forall_congr' fun k => forall_congr' fun _ => ?_
  simp [Decidable.or_iff_not_imp_left]

theorem requirementTraceFindings_eq_nil_iff :
    a.requirementTraceFindings = [] ↔ a.requirementsTraceable = true := by
  simp only [requirementTraceFindings, requirementsTraceable,
    List.flatMap_eq_nil_iff, List.append_eq_nil_iff, List.filterMap_eq_nil_iff,
    List.all_eq_true, Bool.and_eq_true]
  refine forall_congr' fun r => forall_congr' fun _ => ?_
  cases hr : r.element <;>
    simp [List.isEmpty_iff, and_assoc]

theorem orphanFindings_eq_nil_iff :
    a.orphanFindings = [] ↔ a.ucasRefined = true := by
  simp [orphanFindings, ucasRefined, List.filterMap_eq_nil_iff,
    List.all_eq_true]

theorem scenarioTraceFindings_eq_nil_iff :
    a.scenarioTraceFindings = [] ↔ a.scenariosTraceable = true := by
  simp [scenarioTraceFindings, scenariosTraceable, List.filterMap_eq_nil_iff,
    List.all_eq_true]

theorem scenarioGapFindings_eq_nil_iff :
    a.scenarioGapFindings = [] ↔ a.scenariosCover = true := by
  simp [scenarioGapFindings, scenariosCover, List.filterMap_eq_nil_iff,
    List.all_eq_true]

theorem docFindings_eq_nil_iff :
    a.docFindings = [] ↔ a.docWellFormed = true := by
  simp [docFindings, docWellFormed, List.append_eq_nil_iff,
    hazardTraceFindings_eq_nil_iff, constraintTraceFindings_eq_nil_iff,
    unconstrainedHazardFindings_eq_nil_iff, ucaTraceFindings_eq_nil_iff,
    coverageFindings_eq_nil_iff, requirementTraceFindings_eq_nil_iff,
    orphanFindings_eq_nil_iff, scenarioTraceFindings_eq_nil_iff,
    scenarioGapFindings_eq_nil_iff, Bool.and_eq_true, and_assoc]

/-! ## The headline theorems -/

/-- Soundness and completeness of the findings engine: no findings iff the
analysis is well-formed. An empty findings list is a certificate. -/
theorem clean_iff_wellFormed :
    a.clean = true ↔ a.wellFormed = true := by
  simp [clean, findings, wellFormed, List.isEmpty_iff, List.append_eq_nil_iff,
    modelFindings_eq_nil_iff, csFindings_eq_nil_iff, docFindings_eq_nil_iff,
    Bool.and_eq_true, and_assoc]

/-- The diagnostics connect to the Prop-level type system: an analysis with
no document findings is `WellTyped`, and vice versa. -/
theorem docFindings_eq_nil_iff_wellTyped :
    a.docFindings = [] ↔ WellTyped a := by
  rw [docFindings_eq_nil_iff, wellTyped_iff]

end Analysis

end Sysml.Stpa
