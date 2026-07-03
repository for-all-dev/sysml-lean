import Sysml.Kernel.Syntax

/-!
# Rendering models back to SysML v2 textual notation

The inverse of the DSL in `Sysml.Dsl`: prints (the supported subset of) a
`Model` in SysML v2 textual notation (§8.2.2). This is a pure function so it
serves both the `#sysml` command (elaboration-time pretty-printing) and, in
the later checker sprint, round-trip testing of the parser.
-/

namespace Sysml.Kernel

/-- The display name of an element, falling back to its id. -/
def Model.nameOf (m : Model) (i : ElementId) : String :=
  match m.find? i with
  | some e => e.name.getD (toString i)
  | none => toString i

/-- `part.port` qualified name for a connector end. -/
def Model.qualifiedPort (m : Model) (p : ElementId) : String :=
  match (m.find? p).bind (·.owner) with
  | some o => m.nameOf o ++ "." ++ m.nameOf p
  | none => m.nameOf p

private def dirKeyword : Direction → String
  | .«in» => "in"
  | .out => "out"
  | .inout => "inout"

private def indentStr (n : Nat) : String :=
  String.join (List.replicate n "  ")

/-- Render one element (and, recursively, its owned members). Fuel-bounded
by ownership depth, hence total on any model. -/
private def renderElement (m : Model) : Nat → Nat → Element → String
  | 0, _, _ => ""
  | fuel + 1, depth, e =>
    let ind := indentStr depth
    let name := e.name.getD (toString e.id)
    let children :=
      String.join ((m.ownedBy e.id).map (renderElement m fuel (depth + 1)))
    let block (header : String) : String :=
      if children.isEmpty then ind ++ header ++ ";\n"
      else ind ++ header ++ " {\n" ++ children ++ ind ++ "}\n"
    let typed (header : String) : String :=
      match (m.definitionOf? e.id).map m.nameOf with
      | some d => header ++ " : " ++ d
      | none => header
    match e.kind with
    | .package => block s!"package {name}"
    | .partDef => block s!"part def {name}"
    | .itemDef => block s!"item def {name}"
    | .portDef => block s!"port def {name}"
    | .attributeDef => block s!"attribute def {name}"
    | .connectionDef => block s!"connection def {name}"
    | .actionDef => block s!"action def {name}"
    | .stateDef => block s!"state def {name}"
    | .requirementDef => block s!"requirement def {name}"
    | .partUsage => block (typed s!"part {name}")
    | .itemUsage => block (typed s!"item {name}")
    | .attributeUsage => block (typed s!"attribute {name}")
    | .actionUsage => block (typed s!"action {name}")
    | .stateUsage => block (typed s!"state {name}")
    | .requirementUsage => block (typed s!"requirement {name}")
    | .portUsage =>
      let d := (e.direction.map dirKeyword).map (· ++ " ") |>.getD ""
      ind ++ d ++ s!"port {name};\n"
    | .flowUsage =>
      let item := match (m.definitionOf? e.id).map m.nameOf with
        | some i => s!" of {i}"
        | none => ""
      let ends := match m.endOf? e.id 0, m.endOf? e.id 1 with
        | some s, some t => s!" from {m.qualifiedPort s} to {m.qualifiedPort t}"
        | _, _ => ""
      ind ++ s!"flow {name}{item}{ends};\n"
    | .connectionUsage =>
      let ends := match m.endOf? e.id 0, m.endOf? e.id 1 with
        | some s, some t => s!" connect {m.qualifiedPort s} to {m.qualifiedPort t}"
        | _, _ => ""
      ind ++ (typed s!"connection {name}") ++ ends ++ ";\n"

/-- Render a whole model in SysML v2 textual notation. -/
def Model.render (m : Model) : String :=
  String.join ((m.elements.filter (·.owner = none)).map
    (renderElement m m.elements.length 0))

end Sysml.Kernel
