import Sysml.View

/-!
# STPA over SysML models

System-Theoretic Process Analysis (Leveson, *Engineering a Safer World*;
STPA Handbook, 2018) on top of the SysML view layer. The vocabulary is
kept Sec-ready: harms are tagged `safety` or `security` (STPA-Sec,
Young & Leveson 2014), so vulnerability-style hazards drop in without
restructuring.

STPA steps embedded here:
1. Purpose of analysis: losses and hazards (`Loss`, `Hazard`).
2. Control structure: roles over part usages, control/feedback typing of
   connections (`ControlStructure`).
3. Unsafe control actions: the four UCA types (`Uca`, `UcaKind`).
4. Loss scenarios: deferred to a later sprint (`Scenario` is a stub).

All well-formedness conditions are `Bool`-valued, so a concrete analysis is
certified end-to-end by `decide`/`rfl`.
-/

namespace Sysml.Stpa

open Sysml.Kernel Sysml.View

/-- Role of a part in the functional control structure. -/
inductive Role where
  | controller
  | actuator
  | sensor
  | controlledProcess
deriving DecidableEq, Repr

/-- A functional control structure over a SysML model: a role assignment for
part usages, and a classification of connections/flows as control-action
paths or feedback paths.

Two relations live over the same node set and must not be conflated
(docs/stpa-typesystem.pdf §1):

- the *authority* relation — control edges between controllers — whose
  transitive closure must be acyclic (`authorityAcyclic`): command
  hierarchies do not loop;
- the *information-flow* relation — control together with feedback — which
  may and should contain cycles (that is what a closed control loop is).

Accordingly, reachability is only ever checked within one relation at a
time (`controlLoopsClosed` uses control edges and feedback edges
separately), never over their union. -/
structure ControlStructure where
  /-- Role of each participating part usage. -/
  roles : List (ElementId × Role)
  /-- Connections/flows carrying control actions (downward edges). -/
  controlPaths : List ElementId
  /-- Connections/flows carrying feedback (upward edges). -/
  feedbackPaths : List ElementId
deriving Repr

namespace ControlStructure

def roleOf? (cs : ControlStructure) (p : ElementId) : Option Role :=
  (cs.roles.find? (·.1 = p)).map (·.2)

/-- Downward edges of the control structure, at the part level. -/
def controlEdges (cs : ControlStructure) (m : Model) : List (ElementId × ElementId) :=
  (links m).filterMap fun l =>
    if cs.controlPaths.contains l.conn then some (l.sourcePart, l.targetPart) else none

/-- Upward edges of the control structure, at the part level. -/
def feedbackEdges (cs : ControlStructure) (m : Model) : List (ElementId × ElementId) :=
  (links m).filterMap fun l =>
    if cs.feedbackPaths.contains l.conn then some (l.sourcePart, l.targetPart) else none

/-- Every role is assigned to an existing part usage, exactly once. -/
def rolesWellFormed (cs : ControlStructure) (m : Model) : Bool :=
  ((cs.roles.map (·.1.toNat)).eraseDups.length = cs.roles.length)
  && cs.roles.all fun (p, _) => m.kindOf? p = some .partUsage

/-- Control and feedback paths are existing connections/flows between parts
that have roles, and respect the control hierarchy: control actions may only
go controller → actuator/process, actuator → process; feedback only
process → sensor/controller, sensor → controller
(STPA Handbook §2.2, generic control loop). -/
def pathsWellFormed (cs : ControlStructure) (m : Model) : Bool :=
  cs.controlPaths.all (fun c => (links m).any (·.conn = c))
  && cs.feedbackPaths.all (fun c => (links m).any (·.conn = c))
  && (cs.controlEdges m).all (fun (s, t) =>
       match cs.roleOf? s, cs.roleOf? t with
       | some .controller, some .actuator => true
       | some .controller, some .controlledProcess => true
       | some .controller, some .controller => true  -- hierarchical control
       | some .actuator, some .controlledProcess => true
       | _, _ => false)
  && (cs.feedbackEdges m).all (fun (s, t) =>
       match cs.roleOf? s, cs.roleOf? t with
       | some .controlledProcess, some .sensor => true
       | some .controlledProcess, some .controller => true
       | some .controller, some .controller => true  -- status reporting upward
       | some .sensor, some .controller => true
       | _, _ => false)

/-- The authority relation: control edges whose endpoints are both
controllers (hierarchical command). -/
def authorityEdges (cs : ControlStructure) (m : Model) : List (ElementId × ElementId) :=
  (cs.controlEdges m).filter fun (s, t) =>
    cs.roleOf? s = some .controller && cs.roleOf? t = some .controller

/-- Authority edges that close a command cycle: an edge `s → t` where
`t` reaches back to `s` (or `s = t`). -/
def authorityViolations (cs : ControlStructure) (m : Model) :
    List (ElementId × ElementId) :=
  let auth := cs.authorityEdges m
  auth.filter fun e => e.1 = e.2 || reachable auth e.2 e.1

/-- The authority relation is a DAG: no controller commands itself, directly
or transitively (docs/stpa-typesystem.pdf §1). Defined as the absence of
violations, so the check and the findings that explain it cannot drift
(`Sysml.Soundness`). -/
def authorityAcyclic (cs : ControlStructure) (m : Model) : Bool :=
  (cs.authorityViolations m).isEmpty

/-- Open loops: (controller, process) pairs where the controller can
influence the process via control paths but no feedback path chain leads
back. -/
def openLoopPairs (cs : ControlStructure) (m : Model) :
    List (ElementId × ElementId) :=
  cs.roles.flatMap fun cr =>
    if cr.2 = .controller then
      cs.roles.filterMap fun pr =>
        if pr.2 = .controlledProcess
            && reachable (cs.controlEdges m) cr.1 pr.1
            && !reachable (cs.feedbackEdges m) pr.1 cr.1 then
          some (cr.1, pr.1)
        else none
    else []

/-- The defining property of a *closed* control loop: whenever a controller
can influence a process via control paths, some feedback path chain leads
back from that process to that controller (STPA Handbook §2.2; a controller
without feedback cannot enforce safety constraints). Defined as the absence
of open loops. -/
def controlLoopsClosed (cs : ControlStructure) (m : Model) : Bool :=
  (cs.openLoopPairs m).isEmpty

/-- All structural conditions on a control structure: role and path
well-kindedness, an acyclic authority hierarchy, and closed control loops. -/
def wellFormed (cs : ControlStructure) (m : Model) : Bool :=
  cs.rolesWellFormed m && cs.pathsWellFormed m && cs.authorityAcyclic m
    && cs.controlLoopsClosed m

end ControlStructure

/-- Whether a harm is a safety harm (accident/loss) or a security harm
(STPA-Sec: loss driven by adversarial action). -/
inductive HarmKind where
  | safety
  | security
deriving DecidableEq, Repr

/-- A loss: something of stakeholder value whose loss is unacceptable
(STPA Handbook, step 1). -/
structure Loss where
  id : Nat
  desc : String
deriving Repr

/-- A hazard (STPA-Sec: vulnerability): a system state that, together with
worst-case environmental conditions, leads to one or more losses. -/
structure Hazard where
  id : Nat
  desc : String
  kind : HarmKind := .safety
  losses : List Nat
deriving Repr

/-- Leveson's four types of unsafe control action (STPA Handbook, step 3). -/
inductive UcaKind where
  /-- Not providing the control action causes a hazard. -/
  | notProviding
  /-- Providing the control action causes a hazard. -/
  | providing
  /-- Providing it too early, too late, or out of order causes a hazard. -/
  | wrongTiming
  /-- Stopping too soon or applying too long causes a hazard. -/
  | wrongDuration
deriving DecidableEq, Repr

/-- Enumeration of all four UCA kinds, for coverage checking. -/
def UcaKind.all : List UcaKind :=
  [.notProviding, .providing, .wrongTiming, .wrongDuration]

/-- Human-readable guide-phrase label (reports, findings, diagrams). -/
def UcaKind.label : UcaKind → String
  | .notProviding => "not providing"
  | .providing => "providing"
  | .wrongTiming => "too early / too late / out of order"
  | .wrongDuration => "stopped too soon / applied too long"

/-- An unsafe control action: a control action (a control path in the model)
that, in a given context, is hazardous in one of the four ways. -/
structure Uca where
  id : Nat
  /-- The control path (connection/flow id) carrying the action. -/
  action : ElementId
  kind : UcaKind
  /-- The context in which the action is unsafe. Informal for now. -/
  context : String
  /-- Hazards this UCA can lead to. Must be nonempty. -/
  hazards : List Nat
deriving Repr

/-- A system-level constraint: a condition the system must satisfy to
prevent one or more hazards (STPA Handbook, step 1). -/
structure SystemConstraint where
  id : Nat
  desc : String
  /-- Hazards this constraint prevents/mitigates. Must be nonempty. -/
  hazards : List Nat
deriving Repr

/-- A controller constraint or requirement, derived from (refining) one or
more UCAs (STPA Handbook, step 3). The totality judgment of the analysis
demands that every UCA be refined by at least one of these — an orphaned
UCA is a non-exhaustiveness error (docs/stpa-typesystem.pdf).

`element` optionally binds the requirement to a SysML `requirementUsage`
in the model, tying the analysis document into the model proper. -/
structure Requirement where
  id : Nat
  desc : String
  /-- UCAs this requirement refines. Must be nonempty. -/
  ucas : List Nat
  element : Option ElementId := none
deriving Repr

/-- A loss scenario: a causal explanation of how a UCA could occur
(STPA step 4). Causal-factor structure is a later sprint; for now a
scenario traces to its UCA with an informal description. -/
structure Scenario where
  id : Nat
  uca : Nat
  desc : String
deriving Repr

/-- A full STPA analysis of a SysML model. The artifacts form the dependency
chain losses ← hazards ← {system constraints, UCAs} ← requirements ←
scenarios (docs/stpa-typesystem.pdf §1). -/
structure Analysis where
  model : Model
  cs : ControlStructure
  losses : List Loss
  hazards : List Hazard
  constraints : List SystemConstraint := []
  ucas : List Uca
  /-- Explicit not-applicable verdicts: (control path, UCA kind, rationale).
  Coverage demands each pair be either a UCA or a justified N/A. -/
  notApplicable : List (ElementId × UcaKind × String) := []
  requirements : List Requirement := []
  scenarios : List Scenario := []
deriving Repr

namespace Analysis

/-- Hazard traceability: every hazard maps to ≥ 1 existing loss. -/
def hazardsTraceable (a : Analysis) : Bool :=
  a.hazards.all fun h =>
    !h.losses.isEmpty && h.losses.all fun l => a.losses.any (·.id = l)

/-- UCA traceability: every UCA names a declared control path and maps to
≥ 1 existing hazard. -/
def ucasTraceable (a : Analysis) : Bool :=
  a.ucas.all fun u =>
    a.cs.controlPaths.contains u.action
    && !u.hazards.isEmpty
    && u.hazards.all fun h => a.hazards.any (·.id = h)

/-- Constraint traceability: every system constraint maps to ≥ 1 existing
hazard. -/
def constraintsTraceable (a : Analysis) : Bool :=
  a.constraints.all fun c =>
    !c.hazards.isEmpty && c.hazards.all fun h => a.hazards.any (·.id = h)

/-- Hazard totality: every hazard is addressed by ≥ 1 system constraint. -/
def hazardsConstrained (a : Analysis) : Bool :=
  a.hazards.all fun h => a.constraints.any fun c => c.hazards.contains h.id

/-- UCA coverage: for every control path and every one of the four UCA
kinds, there is either a UCA or an explicit, justified N/A verdict. -/
def ucasCover (a : Analysis) : Bool :=
  a.cs.controlPaths.all fun c =>
    UcaKind.all.all fun k =>
      a.ucas.any (fun u => u.action = c && u.kind = k)
      || a.notApplicable.any (fun na => na.1 = c && na.2.1 = k)

/-- Requirement traceability: every requirement refines ≥ 1 existing UCA
(and, when bound to the model, points at a requirement usage). -/
def requirementsTraceable (a : Analysis) : Bool :=
  a.requirements.all fun r =>
    !r.ucas.isEmpty && r.ucas.all (fun u => a.ucas.any (·.id = u))
    && (match r.element with
        | some e => a.model.kindOf? e = some .requirementUsage
        | none => true)

/-- UCA totality — the central judgment (docs/stpa-typesystem.pdf): every
UCA is refined by ≥ 1 controller requirement. An orphaned UCA is exactly a
non-exhaustiveness error. -/
def ucasRefined (a : Analysis) : Bool :=
  a.ucas.all fun u => a.requirements.any fun r => r.ucas.contains u.id

/-- Scenario traceability: every loss scenario explains an existing UCA. -/
def scenariosTraceable (a : Analysis) : Bool :=
  a.scenarios.all fun s => a.ucas.any (·.id = s.uca)

/-- Scenario totality (STPA step 4): every UCA has ≥ 1 loss scenario.
Scenarios are still informal descriptions (causal-factor structure is a
later sprint), but their *existence* per UCA is method-mandated (STPA
Handbook step 4) and enforced. -/
def scenariosCover (a : Analysis) : Bool :=
  a.ucas.all fun u => a.scenarios.any (·.uca = u.id)

/-- All document-level judgments: referential well-kindedness of every
artifact plus the two totality conditions (hazards constrained, UCAs
refined). This is the Bool decision procedure for `Sysml.Stpa.WellTyped`
(see `Sysml.Typing`). -/
def docWellFormed (a : Analysis) : Bool :=
  a.hazardsTraceable
  && a.constraintsTraceable
  && a.hazardsConstrained
  && a.ucasTraceable
  && a.ucasCover
  && a.requirementsTraceable
  && a.ucasRefined
  && a.scenariosTraceable
  && a.scenariosCover

/-- The whole analysis is well-formed: the model is well-formed SysML, the
control structure is a closed-loop structure with an acyclic authority
hierarchy over it, and the analysis document is well-typed (traceable,
covered, and total). -/
def wellFormed (a : Analysis) : Bool :=
  a.model.wellFormed
  && a.cs.wellFormed a.model
  && a.docWellFormed

end Analysis

end Sysml.Stpa
