import Sysml.Kernel.Syntax

/-!
# Deep layer: well-formedness

Decidable (`Bool`-valued) well-formedness rules for the abstract-syntax
graph, drawn from the constraints of §7.5 (namespaces), §7.6 (definition and
usage), and §7.13 (connections). Keeping every rule executable means models
can be certified by `decide` / `rfl` and, in the later checker sprint, the
same code becomes the checker.
-/

namespace Sysml.Kernel

namespace Model

/-- Element ids are pairwise distinct (member distinguishability, §7.5). -/
def uniqueIds (m : Model) : Bool :=
  let ids := m.elements.map (·.id.toNat)
  ids.eraseDups.length = ids.length

/-- Every `owner` reference resolves, and the owner occurs *earlier* in the
element list. The ordering requirement makes ownership a forest (no cycles)
without a separate acyclicity check. -/
def ownersWellFounded (m : Model) : Bool :=
  go [] m.elements
where
  go (seen : List ElementId) : List Element → Bool
    | [] => true
    | e :: rest =>
      (match e.owner with
       | none => true
       | some o => seen.contains o)
      && go (e.id :: seen) rest

/-- Both endpoints of every relationship resolve to elements. -/
def relEndpointsResolve (m : Model) : Bool :=
  m.rels.all fun r => (m.find? r.source).isSome && (m.find? r.target).isSome

/-- Feature typing relates a usage to a definition of the matching kind
(§7.6.4): e.g. a `partUsage` may only be typed by a `partDef`. -/
def typingsKindCorrect (m : Model) : Bool :=
  m.rels.all fun r =>
    match r.kind with
    | .featureTyping =>
      match m.kindOf? r.source, m.kindOf? r.target with
      | some ku, some kd => ku.definitionKind = some kd
      | _, _ => false
    | _ => true

/-- Each usage has at most one typing (we embed single typing; SysML allows
multiple, §7.6.4, which we may generalize later). -/
def typingsUnique (m : Model) : Bool :=
  m.elements.all fun e =>
    (m.rels.countP fun r => r.kind = .featureTyping ∧ r.source = e.id) ≤ 1

/-- Specialization relates two definitions of the same kind (§7.6.5). -/
def specializationsKindCorrect (m : Model) : Bool :=
  m.rels.all fun r =>
    match r.kind with
    | .specialization =>
      match m.kindOf? r.source, m.kindOf? r.target with
      | some k₁, some k₂ => k₁.isDefinition && k₁ = k₂
      | _, _ => false
    | _ => true

/-- Connector ends: only connection and flow usages have ends; each has
exactly ends 0 and 1, each attached to a port usage (§7.13, §7.16; we embed
binary connections only). -/
def connectorEndsCorrect (m : Model) : Bool :=
  endsAreOnConnectors && connectorsBinary
where
  endsAreOnConnectors : Bool :=
    m.rels.all fun r =>
      match r.kind with
      | .connectorEnd i =>
        (i = 0 || i = 1)
        && (m.kindOf? r.source = some .connectionUsage
            || m.kindOf? r.source = some .flowUsage)
        && m.kindOf? r.target = some .portUsage
      | _ => true
  connectorsBinary : Bool :=
    m.elements.all fun e =>
      if e.kind = .connectionUsage ∨ e.kind = .flowUsage then
        (m.endOf? e.id 0).isSome && (m.endOf? e.id 1).isSome
        && (m.rels.countP fun r =>
              (r.kind = .connectorEnd 0 ∨ r.kind = .connectorEnd 1)
              ∧ r.source = e.id) = 2
      else true

/-- Every port usage has a direction; only ports and flows may have one. -/
def directionsPlaced (m : Model) : Bool :=
  m.elements.all fun e =>
    if e.kind = .portUsage then e.direction.isSome
    else if e.kind = .flowUsage then true
    else e.direction.isNone

/-- Items may only flow from a source to a conformant target (out → in,
inout free; §7.13, §7.16): direction conformance across every connector. -/
def flowsDirected (m : Model) : Bool :=
  m.elements.all fun e =>
    if e.kind = .connectionUsage ∨ e.kind = .flowUsage then
      match m.endOf? e.id 0, m.endOf? e.id 1 with
      | some s, some t =>
        match (m.find? s).bind (·.direction), (m.find? t).bind (·.direction) with
        | some ds, some dt => ds.conforms dt
        | _, _ => false
      | _, _ => false
    else true

/-- The conjunction of all well-formedness rules. -/
def wellFormed (m : Model) : Bool :=
  m.uniqueIds
  && m.ownersWellFounded
  && m.relEndpointsResolve
  && m.typingsKindCorrect
  && m.typingsUnique
  && m.specializationsKindCorrect
  && m.connectorEndsCorrect
  && m.directionsPlaced
  && m.flowsDirected

end Model

end Sysml.Kernel
