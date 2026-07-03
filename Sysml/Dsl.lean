import Lean
import Sysml.Kernel.Render

/-!
# `sysml` / `#sysml`: SysML v2 textual notation inside Lean

Lean's extensible parser lets us embed (a subset of) the SysML v2 textual
notation (§8.2.2) directly in `.lean` files. The `sysml` command parses the
notation with Lean's own parser and elaborates it into a deep
`Sysml.Kernel.Model` graph — so the decidable well-formedness rules and
STPA machinery apply to models written in SysML surface syntax:

```
sysml pumpModel {
  package InsulinPumpSystem {
    part def Controller;
    part pumpController : Controller {
      out port cmdOut;
    }
    flow deliverCmd of InsulinCommand
      from pumpController.cmdOut to pumpMotor.cmdIn;
  }
}
```

The other direction, `#sysml pumpModel`, evaluates a `Model` definition and
pretty-prints it back as textual notation (see `Sysml.Kernel.Render`) —
delaboration to SysML rather than to Lean terms.

Element ids are assigned sequentially during elaboration; recover them by
name with `Model.idOf` rather than hard-coding numbers.
-/

namespace Sysml.Dsl

open Lean Elab Command
open Sysml.Kernel

/-! ## Surface syntax (subset of §8.2.2) -/

-- `behavior := symbol` makes the category dispatch on identifier-like
-- leading tokens, which the non-reserved keywords below require.
declare_syntax_cat sysml_member (behavior := symbol)

-- SysML keywords are declared *non-reserved* (`&"…"`) wherever Lean allows,
-- so they act as keywords only inside `sysml` blocks and remain usable as
-- ordinary identifiers elsewhere. (`def`, `in`, `from` are Lean keywords
-- already and must stay reserved.)
syntax &"package" ident "{" sysml_member* "}" : sysml_member
syntax &"part" "def" ident ";" : sysml_member
syntax &"item" "def" ident ";" : sysml_member
syntax &"part" ident (":" ident)? ";" : sysml_member
syntax &"part" ident (":" ident)? "{" sysml_member* "}" : sysml_member
syntax "in" &"port" ident ";" : sysml_member
syntax &"out" &"port" ident ";" : sysml_member
syntax &"inout" &"port" ident ";" : sysml_member
syntax &"flow" ident (&"of" ident)? "from" ident &"to" ident ";" : sysml_member
syntax &"connect" ident &"to" ident ";" : sysml_member

/-! ## Elaboration state -/

private structure ElemDesc where
  id : Nat
  kind : ElementKind
  name : String
  owner : Option Nat
  dir : Option Direction := none

/-- A reference to be resolved after the whole model is collected, so
declaration order doesn't matter (forward references are fine). -/
private inductive Pending where
  /-- `featureTyping`: usage id, definition name. -/
  | typing (usage : Nat) (defName : String) (ref : Syntax)
  /-- Connector ends: connector id, `part.port` names for ends 0 and 1. -/
  | ends (conn : Nat) (src trg : Lean.Name) (ref : Syntax)

private structure St where
  nextId : Nat := 1
  elems : Array ElemDesc := #[]
  pending : Array Pending := #[]

private abbrev DslM := StateT St CommandElabM

private def fresh : DslM Nat := do
  let n := (← get).nextId
  modify fun s => { s with nextId := n + 1 }
  return n

private def push (d : ElemDesc) : DslM Unit :=
  modify fun s => { s with elems := s.elems.push d }

private def pend (p : Pending) : DslM Unit :=
  modify fun s => { s with pending := s.pending.push p }

/-! ## Walking the surface syntax -/

private partial def walkMember (owner : Option Nat) (stx : TSyntax `sysml_member) :
    DslM Unit := do
  match stx with
  | `(sysml_member| package $id { $ms* }) => do
    let n ← fresh
    push { id := n, kind := .package, name := id.getId.toString, owner }
    for m in ms do walkMember (some n) m
  | `(sysml_member| part def $id ;) => do
    push { id := ← fresh, kind := .partDef, name := id.getId.toString, owner }
  | `(sysml_member| item def $id ;) => do
    push { id := ← fresh, kind := .itemDef, name := id.getId.toString, owner }
  | `(sysml_member| part $id $[: $ty]? ;) =>
    partUsage id ty #[]
  | `(sysml_member| part $id $[: $ty]? { $ms* }) =>
    partUsage id ty ms
  | `(sysml_member| in port $id ;) => addPort id .«in»
  | `(sysml_member| out port $id ;) => addPort id .out
  | `(sysml_member| inout port $id ;) => addPort id .inout
  | `(sysml_member| flow $id $[of $ty]? from $src to $trg ;) => do
    let n ← fresh
    push { id := n, kind := .flowUsage, name := id.getId.toString, owner }
    if let some ty := ty then
      pend (.typing n ty.getId.toString ty)
    pend (.ends n src.getId trg.getId stx)
  | `(sysml_member| connect $src to $trg ;) => do
    let n ← fresh
    push { id := n, kind := .connectionUsage, name := s!"connection{n}", owner }
    pend (.ends n src.getId trg.getId stx)
  | _ => throwErrorAt stx "unsupported SysML member"
where
  partUsage (id : Ident) (ty : Option Ident) (ms : Array (TSyntax `sysml_member)) :
      DslM Unit := do
    let n ← fresh
    push { id := n, kind := .partUsage, name := id.getId.toString, owner }
    if let some ty := ty then
      pend (.typing n ty.getId.toString ty)
    for m in ms do walkMember (some n) m
  addPort (id : Ident) (d : Direction) : DslM Unit := do
    push { id := ← fresh, kind := .portUsage, name := id.getId.toString, owner,
           dir := some d }

/-! ## Resolving pending references -/

private def findDef (st : St) (name : String) : Option Nat :=
  (st.elems.find? fun d => d.kind.isDefinition && d.name = name).map (·.id)

/-- Resolve `part.port` (or a bare port name, if unambiguous). -/
private def findPort (st : St) (n : Lean.Name) : Option Nat :=
  match n.components with
  | [p] =>
    (st.elems.find? fun d => d.kind = .portUsage && d.name = p.toString).map (·.id)
  | [partName, p] => do
    let pd ← st.elems.find? fun d => d.kind = .partUsage && d.name = partName.toString
    let portElem ← st.elems.find? fun d =>
      d.kind = .portUsage && d.name = p.toString && d.owner = some pd.id
    return portElem.id
  | _ => none

private def resolve (st : St) (p : Pending) :
    CommandElabM (Array (RelKind × Nat × Nat)) := do
  match p with
  | .typing u defName ref =>
    match findDef st defName with
    | some d => return #[(.featureTyping, u, d)]
    | none => throwErrorAt ref "unknown definition '{defName}'"
  | .ends c src trg ref =>
    match findPort st src, findPort st trg with
    | some s, some t => return #[(.connectorEnd 0, c, s), (.connectorEnd 1, c, t)]
    | none, _ => throwErrorAt ref "cannot resolve port '{src}'"
    | _, none => throwErrorAt ref "cannot resolve port '{trg}'"

/-! ## Emitting the `Model` term -/

private def kindIdent : ElementKind → Ident
  | .attributeDef => mkCIdent ``ElementKind.attributeDef
  | .attributeUsage => mkCIdent ``ElementKind.attributeUsage
  | .itemDef => mkCIdent ``ElementKind.itemDef
  | .itemUsage => mkCIdent ``ElementKind.itemUsage
  | .partDef => mkCIdent ``ElementKind.partDef
  | .partUsage => mkCIdent ``ElementKind.partUsage
  | .portDef => mkCIdent ``ElementKind.portDef
  | .portUsage => mkCIdent ``ElementKind.portUsage
  | .connectionDef => mkCIdent ``ElementKind.connectionDef
  | .connectionUsage => mkCIdent ``ElementKind.connectionUsage
  | .flowUsage => mkCIdent ``ElementKind.flowUsage
  | .actionDef => mkCIdent ``ElementKind.actionDef
  | .actionUsage => mkCIdent ``ElementKind.actionUsage
  | .stateDef => mkCIdent ``ElementKind.stateDef
  | .stateUsage => mkCIdent ``ElementKind.stateUsage
  | .requirementDef => mkCIdent ``ElementKind.requirementDef
  | .requirementUsage => mkCIdent ``ElementKind.requirementUsage
  | .package => mkCIdent ``ElementKind.package

private def dirIdent : Direction → Ident
  | .«in» => mkCIdent ``Direction.«in»
  | .out => mkCIdent ``Direction.out
  | .inout => mkCIdent ``Direction.inout

private def elemTerm (d : ElemDesc) : CommandElabM Term := do
  let owner ← match d.owner with
    | some o => `(some ⟨$(quote o)⟩)
    | none => `(none)
  let dir ← match d.dir with
    | some dd => `(some $(dirIdent dd))
    | none => `(none)
  `({ id := ⟨$(quote d.id)⟩, kind := $(kindIdent d.kind),
      name := some $(quote d.name), owner := $owner, direction := $dir })

private def relTerm : RelKind × Nat × Nat → CommandElabM Term
  | (.featureTyping, s, t) =>
    `({ kind := $(mkCIdent ``RelKind.featureTyping),
        source := ⟨$(quote s)⟩, target := ⟨$(quote t)⟩ })
  | (.specialization, s, t) =>
    `({ kind := $(mkCIdent ``RelKind.specialization),
        source := ⟨$(quote s)⟩, target := ⟨$(quote t)⟩ })
  | (.connectorEnd i, s, t) =>
    `({ kind := $(mkCIdent ``RelKind.connectorEnd) $(quote i),
        source := ⟨$(quote s)⟩, target := ⟨$(quote t)⟩ })

/-- `sysml name { members }`: elaborate SysML v2 textual notation into a
`def name : Sysml.Kernel.Model`. -/
elab "sysml" name:ident "{" members:sysml_member* "}" : command => do
  let (_, st) ← (members.forM (walkMember none)).run {}
  let rels := (← st.pending.mapM (resolve st)).flatten
  let elemTerms ← st.elems.mapM elemTerm
  let relTerms ← rels.mapM relTerm
  elabCommand (← `(def $name : Sysml.Kernel.Model :=
    { elements := [$elemTerms,*], rels := [$relTerms,*] }))

/-! ## `#sysml`: delaborate a model back to textual notation -/

private unsafe def evalModelUnsafe (env : Environment) (opts : Options)
    (n : Lean.Name) : Except String Model :=
  env.evalConst Model opts n

@[implemented_by evalModelUnsafe]
private def evalModel (_ : Environment) (_ : Options) (_ : Lean.Name) :
    Except String Model := .error "compiler not available"

/-- `#sysml m`: print the model `m` in SysML v2 textual notation. -/
elab "#sysml" id:ident : command => do
  let n ← liftCoreM (realizeGlobalConstNoOverloadWithInfo id)
  match evalModel (← getEnv) (← getOptions) n with
  | .ok m => logInfo (m.render)
  | .error e => throwErrorAt id "cannot evaluate '{n}' as a Model: {e}"

end Sysml.Dsl
