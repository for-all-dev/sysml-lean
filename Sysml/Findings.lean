import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# Findings: structured diagnostics for the checker

The Bool-valued judgments say *whether* an analysis is well-typed; findings
say *what is wrong and where*. Each `Finding` names the violated check, a
severity, the offending subject (artifact id, edge, or coverage cell), and a
human-readable message. This is the substrate for `sysml check --json`,
findings diffs between revisions, and PR comments (docs/ci-product.agents.md).

Severities: `error` findings are exactly the failures of `Analysis.wellFormed`;
`info` findings surface judgments that are deliberately not yet enforced
(step-4 scenario coverage).
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

/-- Coarse findings for the SysML model itself: one per violated rule. -/
def modelFindings (a : Analysis) : List Finding :=
  let m := a.model
  let rules : List (String × Bool × String) := [
    ("model-unique-ids", m.uniqueIds, "element ids are not pairwise distinct"),
    ("model-ownership", m.ownersWellFounded, "an owner reference is dangling or follows its owned element"),
    ("model-rel-endpoints", m.relEndpointsResolve, "a relationship endpoint does not resolve"),
    ("model-typing-kinds", m.typingsKindCorrect, "a feature typing relates mismatched kinds"),
    ("model-typing-unique", m.typingsUnique, "a usage has more than one typing"),
    ("model-specializations", m.specializationsKindCorrect, "a specialization relates mismatched kinds"),
    ("model-connector-ends", m.connectorEndsCorrect, "a connector does not have exactly ends 0 and 1 on port usages"),
    ("model-directions", m.directionsPlaced, "a direction is missing from a port or present on a non-port"),
    ("model-flow-conformance", m.flowsDirected, "an item flows against port directions")
  ]
  rules.filterMap fun (check, ok, msg) =>
    if ok then none else some (finding check "model" msg)

/-- Findings for the control structure: role/path well-kindedness, authority
cycles (per cycle-closing edge), and open control loops (per
controller-process pair). -/
def csFindings (a : Analysis) : List Finding :=
  let cs := a.cs
  let m := a.model
  let roles :=
    if cs.rolesWellFormed m then []
    else [finding "cs-roles" "control structure"
      "a role is assigned twice or to something that is not a part usage"]
  let paths :=
    if cs.pathsWellFormed m then []
    else [finding "cs-paths" "control structure"
      "a control/feedback path is not a connection between role-bearing parts, or violates the control-loop role pattern"]
  let auth := cs.authorityEdges m
  let cycles := auth.filterMap fun e =>
    if e.1 = e.2 || reachable auth e.2 e.1 then
      some (finding "authority-cycle" (a.edgeName e)
        s!"authority must be a DAG, but the edge {a.edgeName e} closes a command cycle")
    else none
  let openLoops := cs.roles.flatMap fun (c, rc) =>
    if rc = .controller then
      cs.roles.filterMap fun (p, rp) =>
        if rp = .controlledProcess
            && reachable (cs.controlEdges m) c p
            && !reachable (cs.feedbackEdges m) p c then
          some (finding "open-loop" (a.edgeName (c, p))
            s!"controller {m.nameOf c} influences {m.nameOf p} but receives no feedback path back")
        else none
    else []
  roles ++ paths ++ cycles ++ openLoops

/-- Findings for the analysis document: broken traces, coverage gaps, and
totality violations (unconstrained hazards, orphaned UCAs). -/
def docFindings (a : Analysis) : List Finding :=
  let hazardTraces := a.hazards.flatMap fun h =>
    (if h.losses.isEmpty then
      [finding "hazard-no-loss" s!"H{h.id}" s!"hazard H{h.id} traces to no loss"]
     else []) ++
    h.losses.filterMap fun l =>
      if a.losses.any (·.id = l) then none
      else some (finding "hazard-dangling-loss" s!"H{h.id}"
        s!"hazard H{h.id} cites unknown loss L{l}")
  let constraintTraces := a.constraints.flatMap fun c =>
    (if c.hazards.isEmpty then
      [finding "constraint-no-hazard" s!"SC{c.id}" s!"constraint SC{c.id} traces to no hazard"]
     else []) ++
    c.hazards.filterMap fun h =>
      if a.hazards.any (·.id = h) then none
      else some (finding "constraint-dangling-hazard" s!"SC{c.id}"
        s!"constraint SC{c.id} cites unknown hazard H{h}")
  let unconstrained := a.hazards.filterMap fun h =>
    if a.constraints.any (·.hazards.contains h.id) then none
    else some (finding "hazard-unconstrained" s!"H{h.id}"
      s!"hazard H{h.id} is addressed by no system-level constraint (totality)")
  let ucaTraces := a.ucas.flatMap fun u =>
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
  let uncovered := a.cs.controlPaths.flatMap fun c =>
    UcaKind.all.filterMap fun k =>
      if a.ucas.any (fun u => u.action = c && u.kind = k)
          || a.notApplicable.any (fun na => na.1 = c && na.2.1 = k) then none
      else some (finding "uca-coverage-gap" s!"{a.model.nameOf c} × {k.label}"
        s!"control path {a.model.nameOf c} has neither a UCA nor a justified N/A for guide phrase '{k.label}'")
  let reqTraces := a.requirements.flatMap fun r =>
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
  let orphans := a.ucas.filterMap fun u =>
    if a.requirements.any (·.ucas.contains u.id) then none
    else some (finding "uca-orphaned" s!"UCA{u.id}"
      s!"UCA{u.id} is refined by no controller requirement — a non-exhaustiveness error (totality)")
  let scenarioTraces := a.scenarios.filterMap fun s =>
    if a.ucas.any (·.id = s.uca) then none
    else some (finding "scenario-dangling-uca" s!"S{s.id}"
      s!"scenario S{s.id} explains unknown UCA{s.uca}")
  let scenarioGaps := a.ucas.filterMap fun u =>
    if a.scenarios.any (·.uca = u.id) then none
    else some (finding "uca-no-scenario" s!"UCA{u.id}"
      s!"UCA{u.id} has no loss scenario yet (step 4)" .info)
  hazardTraces ++ constraintTraces ++ unconstrained ++ ucaTraces ++ uncovered
    ++ reqTraces ++ orphans ++ scenarioTraces ++ scenarioGaps

/-- All findings for an analysis, most severe first. `error` findings are
the failures of `wellFormed`; `info` findings are advisory. -/
def findings (a : Analysis) : List Finding :=
  let all := a.modelFindings ++ a.csFindings ++ a.docFindings
  (all.filter (·.severity = .error)) ++ (all.filter (·.severity = .warning))
    ++ (all.filter (·.severity = .info))

/-- No error-severity findings. Intended to coincide with `wellFormed`
(consistency lemma is planned, see docs/plan.agents.md). -/
def clean (a : Analysis) : Bool :=
  a.findings.all (·.severity ≠ .error)

end Analysis

end Sysml.Stpa
