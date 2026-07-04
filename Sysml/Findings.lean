import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# Findings: structured diagnostics for the checker

The Bool-valued judgments say *whether* an analysis is well-typed; findings
say *what is wrong and where*. Each `Finding` names the violated check, a
severity, the offending subject (artifact id, edge, or coverage cell), and a
human-readable message. This is the substrate for `sysml check --json`,
findings diffs between revisions, and PR comments (docs/ci-product.agents.md).

Every current producer emits `error` severity, and `Sysml.Soundness` proves
the engine sound and complete: `clean ↔ wellFormed`. The `warning`/`info`
severities are reserved for future advisory checks.
-/

namespace Sysml.Stpa

open Sysml.Kernel Sysml.View

inductive Severity where
  | error
  | warning
  | info
deriving DecidableEq, Repr

def Severity.label : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

/-- One diagnostic. `(check, subject)` is the stable identity used when
diffing findings across revisions; `message` is presentation. -/
structure Finding where
  check : String
  severity : Severity
  subject : String
  message : String
deriving DecidableEq, Repr

private def finding (check : String) (subject message : String)
    (severity : Severity := .error) : Finding :=
  { check, severity, subject, message }

namespace Analysis

private def edgeName (a : Analysis) (e : ElementId × ElementId) : String :=
  s!"{a.model.nameOf e.1} → {a.model.nameOf e.2}"

/-- `[]` when the check passes, one finding when it fails. (Public so
`Sysml.Soundness` can state its lemma; not intended for direct use.) -/
def guardFinding (ok : Bool) (check subject message : String) : List Finding :=
  if ok then [] else [finding check subject message]

/-- Coarse findings for the SysML model itself: one per violated rule. -/
def modelFindings (a : Analysis) : List Finding :=
  guardFinding a.model.uniqueIds "model-unique-ids" "model"
    "element ids are not pairwise distinct"
  ++ guardFinding a.model.ownersWellFounded "model-ownership" "model"
    "an owner reference is dangling or follows its owned element"
  ++ guardFinding a.model.relEndpointsResolve "model-rel-endpoints" "model"
    "a relationship endpoint does not resolve"
  ++ guardFinding a.model.typingsKindCorrect "model-typing-kinds" "model"
    "a feature typing relates mismatched kinds"
  ++ guardFinding a.model.typingsUnique "model-typing-unique" "model"
    "a usage has more than one typing"
  ++ guardFinding a.model.specializationsKindCorrect "model-specializations" "model"
    "a specialization relates mismatched kinds"
  ++ guardFinding a.model.connectorEndsCorrect "model-connector-ends" "model"
    "a connector does not have exactly ends 0 and 1 on port usages"
  ++ guardFinding a.model.directionsPlaced "model-directions" "model"
    "a direction is missing from a port or present on a non-port"
  ++ guardFinding a.model.flowsDirected "model-flow-conformance" "model"
    "an item flows against port directions"

/-- Findings for the control structure: role/path well-kindedness, authority
cycles (per cycle-closing edge, from `authorityViolations`), and open
control loops (per controller-process pair, from `openLoopPairs`). -/
def csFindings (a : Analysis) : List Finding :=
  guardFinding (a.cs.rolesWellFormed a.model) "cs-roles" "control structure"
    "a role is assigned twice or to something that is not a part usage"
  ++ guardFinding (a.cs.pathsWellFormed a.model) "cs-paths" "control structure"
    "a control/feedback path is not a connection between role-bearing parts, or violates the control-loop role pattern"
  ++ ((a.cs.authorityViolations a.model).map fun e =>
      finding "authority-cycle" (a.edgeName e)
        s!"authority must be a DAG, but the edge {a.edgeName e} closes a command cycle")
  ++ ((a.cs.openLoopPairs a.model).map fun e =>
      finding "open-loop" (a.edgeName e)
        s!"controller {a.model.nameOf e.1} influences {a.model.nameOf e.2} but receives no feedback path back")

/-! Document-level producers, one per conjunct of `Analysis.docWellFormed`.
Each is a separate definition so the soundness lemmas in `Sysml.Soundness`
can address them individually. -/

/-- `hazardsTraceable` violations. -/
def hazardTraceFindings (a : Analysis) : List Finding :=
  a.hazards.flatMap fun h =>
    (if h.losses.isEmpty then
      [finding "hazard-no-loss" s!"H{h.id}" s!"hazard H{h.id} traces to no loss"]
     else []) ++
    h.losses.filterMap fun l =>
      if a.losses.any (·.id = l) then none
      else some (finding "hazard-dangling-loss" s!"H{h.id}"
        s!"hazard H{h.id} cites unknown loss L{l}")

/-- `constraintsTraceable` violations. -/
def constraintTraceFindings (a : Analysis) : List Finding :=
  a.constraints.flatMap fun c =>
    (if c.hazards.isEmpty then
      [finding "constraint-no-hazard" s!"SC{c.id}" s!"constraint SC{c.id} traces to no hazard"]
     else []) ++
    c.hazards.filterMap fun h =>
      if a.hazards.any (·.id = h) then none
      else some (finding "constraint-dangling-hazard" s!"SC{c.id}"
        s!"constraint SC{c.id} cites unknown hazard H{h}")

/-- `hazardsConstrained` violations (totality). -/
def unconstrainedHazardFindings (a : Analysis) : List Finding :=
  a.hazards.filterMap fun h =>
    if a.constraints.any (·.hazards.contains h.id) then none
    else some (finding "hazard-unconstrained" s!"H{h.id}"
      s!"hazard H{h.id} is addressed by no system-level constraint (totality)")

/-- `ucasTraceable` violations. -/
def ucaTraceFindings (a : Analysis) : List Finding :=
  a.ucas.flatMap fun u =>
    (if a.cs.controlPaths.contains u.action then []
     else [finding "uca-unknown-action" s!"UCA{u.id}"
       s!"UCA{u.id} names {a.model.nameOf u.action}, which is not a declared control path"]) ++
    (if u.hazards.isEmpty then
      [finding "uca-no-hazard" s!"UCA{u.id}" s!"UCA{u.id} traces to no hazard"]
     else []) ++
    u.hazards.filterMap fun h =>
      if a.hazards.any (·.id = h) then none
      else some (finding "uca-dangling-hazard" s!"UCA{u.id}"
        s!"UCA{u.id} cites unknown hazard H{h}")

/-- `ucasCover` violations: uncovered (control path × guide phrase) cells. -/
def coverageFindings (a : Analysis) : List Finding :=
  a.cs.controlPaths.flatMap fun c =>
    UcaKind.all.filterMap fun k =>
      if a.ucas.any (fun u => u.action = c && u.kind = k)
          || a.notApplicable.any (fun na => na.1 = c && na.2.1 = k) then none
      else some (finding "uca-coverage-gap" s!"{a.model.nameOf c} × {k.label}"
        s!"control path {a.model.nameOf c} has neither a UCA nor a justified N/A for guide phrase '{k.label}'")

/-- `requirementsTraceable` violations. -/
def requirementTraceFindings (a : Analysis) : List Finding :=
  a.requirements.flatMap fun r =>
    (if r.ucas.isEmpty then
      [finding "requirement-no-uca" s!"R{r.id}" s!"requirement R{r.id} refines no UCA"]
     else []) ++
    (r.ucas.filterMap fun u =>
      if a.ucas.any (·.id = u) then none
      else some (finding "requirement-dangling-uca" s!"R{r.id}"
        s!"requirement R{r.id} cites unknown UCA{u}")) ++
    (match r.element with
     | some e =>
       if a.model.kindOf? e = some .requirementUsage then []
       else [finding "requirement-bad-element" s!"R{r.id}"
         s!"requirement R{r.id} binds to {e}, which is not a requirement usage in the model"]
     | none => [])

/-- `ucasRefined` violations: orphaned UCAs (totality). -/
def orphanFindings (a : Analysis) : List Finding :=
  a.ucas.filterMap fun u =>
    if a.requirements.any (·.ucas.contains u.id) then none
    else some (finding "uca-orphaned" s!"UCA{u.id}"
      s!"UCA{u.id} is refined by no controller requirement — a non-exhaustiveness error (totality)")

/-- `scenariosTraceable` violations. -/
def scenarioTraceFindings (a : Analysis) : List Finding :=
  a.scenarios.filterMap fun s =>
    if a.ucas.any (·.id = s.uca) then none
    else some (finding "scenario-dangling-uca" s!"S{s.id}"
      s!"scenario S{s.id} explains unknown UCA{s.uca}")

/-- `scenariosCover` violations: UCAs without a loss scenario (step 4). -/
def scenarioGapFindings (a : Analysis) : List Finding :=
  a.ucas.filterMap fun u =>
    if a.scenarios.any (·.uca = u.id) then none
    else some (finding "uca-no-scenario" s!"UCA{u.id}"
      s!"UCA{u.id} has no loss scenario (step 4)")

/-- Findings for the analysis document: broken traces, coverage gaps, and
totality violations, one producer per conjunct of `docWellFormed`. -/
def docFindings (a : Analysis) : List Finding :=
  a.hazardTraceFindings ++ a.constraintTraceFindings
    ++ a.unconstrainedHazardFindings ++ a.ucaTraceFindings
    ++ a.coverageFindings ++ a.requirementTraceFindings ++ a.orphanFindings
    ++ a.scenarioTraceFindings ++ a.scenarioGapFindings

/-- All findings for an analysis, in artifact-chain order. -/
def findings (a : Analysis) : List Finding :=
  a.modelFindings ++ a.csFindings ++ a.docFindings

/-- No findings. Coincides with `wellFormed` — this is proved, not intended:
see `Analysis.clean_iff_wellFormed` in `Sysml.Soundness`. (Every current
producer emits error severity; when advisory checks appear, `clean` should
become "no *error* findings".) -/
def clean (a : Analysis) : Bool :=
  a.findings.isEmpty

end Analysis

end Sysml.Stpa
