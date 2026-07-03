import Sysml.Core

/-!
# Deep layer: abstract syntax graph

A deep embedding of (a subset of) the SysML v2 abstract syntax (§8.3).
Following the MOF metamodel, a model is a *graph*: a list of elements plus a
list of relationships between them, rather than a mutually-inductive AST.
This mirrors how the spec itself presents the language (elements and
relationships, §7.2) and later gives us a direct target for parsing the
textual notation (§8.2.2).

Ownership (owning membership, §7.5) is stored directly on each element as an
optional `owner`; the acyclicity of the ownership forest is obtained by a
well-formedness rule requiring owners to precede their owned elements in the
element list (see `Sysml.Kernel.WellFormed`).
-/

namespace Sysml.Kernel

/-- Untyped element identifier for the deep layer. -/
structure ElementId where
  toNat : Nat
deriving DecidableEq, Repr

instance : ToString ElementId := ⟨fun i => s!"#{i.toNat}"⟩

/-- The metaclasses we embed (a subset of §8.3). Definitions and usages come
in pairs, reflecting the definition/usage duality of §7.6. -/
inductive ElementKind where
  -- §7.7 attributes
  | attributeDef | attributeUsage
  -- §7.10 items
  | itemDef | itemUsage
  -- §7.11 parts
  | partDef | partUsage
  -- §7.12 ports
  | portDef | portUsage
  -- §7.13 connections
  | connectionDef | connectionUsage
  -- §7.16 flows
  | flowUsage
  -- §7.17 actions
  | actionDef | actionUsage
  -- §7.18 states
  | stateDef | stateUsage
  -- §7.21 requirements
  | requirementDef | requirementUsage
  -- §7.5 packages
  | package
deriving DecidableEq, Repr

/-- Is this kind a definition (classifier) as opposed to a usage (feature)? -/
def ElementKind.isDefinition : ElementKind → Bool
  | .attributeDef | .itemDef | .partDef | .portDef | .connectionDef
  | .actionDef | .stateDef | .requirementDef => true
  | _ => false

/-- Is this kind a usage (feature)? Packages are neither. -/
def ElementKind.isUsage : ElementKind → Bool
  | .attributeUsage | .itemUsage | .partUsage | .portUsage | .connectionUsage
  | .flowUsage | .actionUsage | .stateUsage | .requirementUsage => true
  | _ => false

/-- The definition kind a usage kind may be typed by (feature typing, §7.6.4).
`flowUsage` is typed by the item definition of its payload. -/
def ElementKind.definitionKind : ElementKind → Option ElementKind
  | .attributeUsage => some .attributeDef
  | .itemUsage => some .itemDef
  | .partUsage => some .partDef
  | .portUsage => some .portDef
  | .connectionUsage => some .connectionDef
  | .flowUsage => some .itemDef
  | .actionUsage => some .actionDef
  | .stateUsage => some .stateDef
  | .requirementUsage => some .requirementDef
  | _ => none

/-- A model element (§7.2). `direction` is meaningful only for port and flow
usages; `doc` holds documentation text (§7.4 annotations, degenerately). -/
structure Element where
  id : ElementId
  kind : ElementKind
  name : Option Name := none
  owner : Option ElementId := none
  direction : Option Direction := none
  doc : Option String := none
deriving DecidableEq, Repr

/-- Relationship kinds (§7.2). `connectorEnd i` attaches end `i` (0 = source,
1 = target) of a connection or flow usage to a feature; `featureTyping` types
a usage by a definition; `specialization` relates definitions (§7.6.5). -/
inductive RelKind where
  | featureTyping
  | specialization
  | connectorEnd (i : Nat)
deriving DecidableEq, Repr

/-- A directed relationship between two elements. -/
structure Relationship where
  kind : RelKind
  source : ElementId
  target : ElementId
deriving DecidableEq, Repr

/-- A model: an abstract-syntax graph (§7.2). -/
structure Model where
  elements : List Element
  rels : List Relationship
deriving Repr

instance : Inhabited Model := ⟨⟨[], []⟩⟩

namespace Model

/-- Look up an element id by (simple) name. With the DSL (`Sysml.Dsl`),
this is how ids assigned during elaboration are recovered. -/
def idOf? (m : Model) (n : Name) : Option ElementId :=
  (m.elements.find? (·.name = some n)).map (·.id)

/-- Like `idOf?`, defaulting to a dangling id — well-formedness checks will
catch a misspelled name downstream. -/
def idOf (m : Model) (n : Name) : ElementId :=
  (m.idOf? n).getD ⟨0⟩

/-- Look up an element by id. -/
def find? (m : Model) (i : ElementId) : Option Element :=
  m.elements.find? (·.id = i)

/-- The kind of an element id, if it exists. -/
def kindOf? (m : Model) (i : ElementId) : Option ElementKind :=
  (m.find? i).map (·.kind)

/-- All elements of a given kind. -/
def ofKind (m : Model) (k : ElementKind) : List Element :=
  m.elements.filter (·.kind = k)

/-- The definition typing a usage, if any (feature typing, §7.6.4). -/
def definitionOf? (m : Model) (u : ElementId) : Option ElementId :=
  (m.rels.find? fun r => r.kind = .featureTyping ∧ r.source = u).map (·.target)

/-- The feature attached to end `i` of connection/flow `c` (§7.13). -/
def endOf? (m : Model) (c : ElementId) (i : Nat) : Option ElementId :=
  (m.rels.find? fun r => r.kind = .connectorEnd i ∧ r.source = c).map (·.target)

/-- Elements directly owned by `o` (owned members, §7.5). -/
def ownedBy (m : Model) (o : ElementId) : List Element :=
  m.elements.filter (·.owner = some o)

/-- Transitive ownership: walk up the owner chain from `x` looking for `a`.
Fuel-bounded by the number of elements, so it terminates on any model. -/
def isAncestorOf (m : Model) (a x : ElementId) : Bool :=
  go m.elements.length x
where
  go : Nat → ElementId → Bool
    | 0, _ => false
    | fuel + 1, y =>
      match m.find? y with
      | none => false
      | some e =>
        match e.owner with
        | none => false
        | some o => o = a || go fuel o

end Model

end Sysml.Kernel
