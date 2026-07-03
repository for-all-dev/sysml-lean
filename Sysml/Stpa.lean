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
paths or feedback paths. -/
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

/-- The defining property of a *closed* control loop: whenever a controller
can influence a process via control paths, some feedback path chain leads
back from that process to that controller (STPA Handbook §2.2; a controller
without feedback cannot enforce safety constraints). -/
def controlLoopsClosed (cs : ControlStructure) (m : Model) : Bool :=
  cs.roles.all fun (c, rc) =>
    if rc = .controller then
      cs.roles.all fun (p, rp) =>
        if rp = .controlledProcess then
          !(reachable (cs.controlEdges m) c p)
          || reachable (cs.feedbackEdges m) p c
        else true
    else true

/-- All structural conditions on a control structure. -/
def wellFormed (cs : ControlStructure) (m : Model) : Bool :=
  cs.rolesWellFormed m && cs.pathsWellFormed m && cs.controlLoopsClosed m

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

/-- A loss scenario (STPA step 4). Stub — elaborated in a later sprint. -/
structure Scenario where
  id : Nat
  uca : Nat
  desc : String
deriving Repr

/-- A full STPA analysis of a SysML model. -/
structure Analysis where
  model : Model
  cs : ControlStructure
  losses : List Loss
  hazards : List Hazard
  ucas : List Uca
  /-- Explicit not-applicable verdicts: (control path, UCA kind, rationale).
  Coverage demands each pair be either a UCA or a justified N/A. -/
  notApplicable : List (ElementId × UcaKind × String) := []
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

/-- UCA coverage: for every control path and every one of the four UCA
kinds, there is either a UCA or an explicit, justified N/A verdict. -/
def ucasCover (a : Analysis) : Bool :=
  a.cs.controlPaths.all fun c =>
    UcaKind.all.all fun k =>
      a.ucas.any (fun u => u.action = c && u.kind = k)
      || a.notApplicable.any (fun (c', k', _) => c' = c && k' = k)

/-- The whole analysis is well-formed: the model is well-formed SysML, the
control structure is a closed-loop structure over it, and the STPA artifacts
are traceable and complete. -/
def wellFormed (a : Analysis) : Bool :=
  a.model.wellFormed
  && a.cs.wellFormed a.model
  && a.hazardsTraceable
  && a.ucasTraceable
  && a.ucasCover

end Analysis

end Sysml.Stpa
