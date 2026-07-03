import Lean
import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# Visualization: DOT (graphviz) and Mermaid renderers

Editor-independent diagram output. Two pure emitters per diagram:

- `toDot` — graphviz input; `#sysml_svg` / `#stpa_svg` shell out to `dot`
  (via `IO.Process`, no FFI) at elaboration time and write an SVG.
- `toMermaid` — Mermaid flowchart text, rendered natively by GitHub/GitLab
  markdown, so diagrams can be pasted straight into READMEs and writeups.

The STPA control-structure diagram follows the usual convention: control
actions are solid downward edges, feedback is dashed (drawn without rank
constraints, so it visually closes the loop upward).
-/

namespace Sysml.Viz

open Sysml.Kernel Sysml.Stpa Sysml.View

private def dotQuote (s : String) : String :=
  "\"" ++ (s.replace "\"" "\\\"") ++ "\""

/-! ## Generic model diagram: parts as nodes, connections/flows as edges -/

/-- The part-level connection graph of a model, as graphviz DOT. -/
def _root_.Sysml.Kernel.Model.toDot (m : Model) (graphName : String := "sysml") : String :=
  let nodes := (m.ofKind .partUsage).map fun e =>
    let ty := match (m.definitionOf? e.id).map m.nameOf with
      | some d => s!" : {d}"
      | none => ""
    s!"  {dotQuote (m.nameOf e.id)} [label={dotQuote (m.nameOf e.id ++ ty)}];\n"
  let edges := (links m).map fun l =>
    s!"  {dotQuote (m.nameOf l.sourcePart)} -> {dotQuote (m.nameOf l.targetPart)} [label={dotQuote (m.nameOf l.conn)}];\n"
  s!"digraph {dotQuote graphName} \{\n  rankdir=LR;\n  node [shape=box, style=rounded, fontname=\"sans-serif\"];\n  edge [fontname=\"sans-serif\", fontsize=10];\n"
    ++ String.join nodes ++ String.join edges ++ "}\n"

/-- The part-level connection graph of a model, as a Mermaid flowchart. -/
def _root_.Sysml.Kernel.Model.toMermaid (m : Model) : String :=
  let nodes := (m.ofKind .partUsage).map fun e =>
    s!"  {m.nameOf e.id}[{m.nameOf e.id}]\n"
  let edges := (links m).map fun l =>
    s!"  {m.nameOf l.sourcePart} -->|{m.nameOf l.conn}| {m.nameOf l.targetPart}\n"
  "flowchart LR\n" ++ String.join nodes ++ String.join edges

/-! ## STPA control-structure diagram -/

private def roleLabel : Role → String
  | .controller => "controller"
  | .actuator => "actuator"
  | .sensor => "sensor"
  | .controlledProcess => "controlled process"

/-- STPA control structure as graphviz DOT: roles annotated, control actions
solid and rank-constraining (downward), feedback dashed (upward). -/
def _root_.Sysml.Stpa.ControlStructure.toDot (cs : ControlStructure) (m : Model)
    (graphName : String := "control_structure") : String :=
  let nodes := cs.roles.map fun (p, r) =>
    s!"  {dotQuote (m.nameOf p)} [label={dotQuote (m.nameOf p ++ "\\n«" ++ roleLabel r ++ "»")}];\n"
  let control := (links m).filterMap fun l =>
    if cs.controlPaths.contains l.conn then
      some s!"  {dotQuote (m.nameOf l.sourcePart)} -> {dotQuote (m.nameOf l.targetPart)} [label={dotQuote (m.nameOf l.conn)}];\n"
    else none
  let feedback := (links m).filterMap fun l =>
    if cs.feedbackPaths.contains l.conn then
      some s!"  {dotQuote (m.nameOf l.sourcePart)} -> {dotQuote (m.nameOf l.targetPart)} [label={dotQuote (m.nameOf l.conn)}, style=dashed, constraint=false];\n"
    else none
  s!"digraph {dotQuote graphName} \{\n  rankdir=TB;\n  node [shape=box, fontname=\"sans-serif\"];\n  edge [fontname=\"sans-serif\", fontsize=10];\n"
    ++ String.join nodes ++ String.join control ++ String.join feedback ++ "}\n"

/-- STPA control structure as a Mermaid flowchart (control solid, feedback
dotted). Paste-able into GitHub markdown. -/
def _root_.Sysml.Stpa.ControlStructure.toMermaid (cs : ControlStructure) (m : Model) : String :=
  let nodes := cs.roles.map fun (p, r) =>
    s!"  {m.nameOf p}[\"{m.nameOf p}<br/>«{roleLabel r}»\"]\n"
  let control := (links m).filterMap fun l =>
    if cs.controlPaths.contains l.conn then
      some s!"  {m.nameOf l.sourcePart} -->|{m.nameOf l.conn}| {m.nameOf l.targetPart}\n"
    else none
  let feedback := (links m).filterMap fun l =>
    if cs.feedbackPaths.contains l.conn then
      some s!"  {m.nameOf l.sourcePart} -.->|{m.nameOf l.conn}| {m.nameOf l.targetPart}\n"
    else none
  "flowchart TB\n" ++ String.join nodes ++ String.join control ++ String.join feedback

/-! ## Elaboration-time commands -/

open Lean Elab Command

private unsafe def evalModelUnsafe (env : Environment) (opts : Options)
    (n : Lean.Name) : Except String Model :=
  env.evalConst Model opts n

@[implemented_by evalModelUnsafe]
private def evalModel (_ : Environment) (_ : Options) (_ : Lean.Name) :
    Except String Model := .error "compiler not available"

private unsafe def evalCsUnsafe (env : Environment) (opts : Options)
    (n : Lean.Name) : Except String ControlStructure :=
  env.evalConst ControlStructure opts n

@[implemented_by evalCsUnsafe]
private def evalCs (_ : Environment) (_ : Options) (_ : Lean.Name) :
    Except String ControlStructure := .error "compiler not available"

private def evalAs {α} (eval : Environment → Options → Lean.Name → Except String α)
    (id : Ident) : CommandElabM α := do
  let n ← liftCoreM (realizeGlobalConstNoOverloadWithInfo id)
  match eval (← getEnv) (← getOptions) n with
  | .ok a => return a
  | .error e => throwErrorAt id "cannot evaluate '{n}': {e}"

/-- Write `path.dot` and run `dot -Tsvg` on it, producing `path`. The DOT
file is kept beside the SVG as a useful artifact. Throws an `IO.userError`
if `dot` (graphviz) fails or is missing. -/
def dotToSvgFile (dotSrc : String) (path : String) : IO Unit := do
  let dotPath := path ++ ".dot"
  IO.FS.writeFile dotPath dotSrc
  let out ← IO.Process.output { cmd := "dot", args := #["-Tsvg", dotPath, "-o", path] }
  if out.exitCode != 0 then
    throw (IO.userError s!"dot failed (is graphviz installed?): {out.stderr}")

private def renderSvg (dotSrc : String) (path : String) : CommandElabM Unit := do
  dotToSvgFile dotSrc path
  logInfo s!"wrote {path}"

/-- `#sysml_dot m`: print the part-connection graph of model `m` as DOT. -/
elab "#sysml_dot" id:ident : command => do
  logInfo (Model.toDot (← evalAs evalModel id))

/-- `#sysml_mermaid m`: print the part-connection graph as Mermaid. -/
elab "#sysml_mermaid" id:ident : command => do
  logInfo (Model.toMermaid (← evalAs evalModel id))

/-- `#stpa_dot cs m`: print the STPA control-structure diagram as DOT. -/
elab "#stpa_dot" cs:ident m:ident : command => do
  logInfo (ControlStructure.toDot (← evalAs evalCs cs) (← evalAs evalModel m))

/-- `#stpa_mermaid cs m`: print the STPA control-structure diagram as
Mermaid (paste-able into GitHub markdown). -/
elab "#stpa_mermaid" cs:ident m:ident : command => do
  logInfo (ControlStructure.toMermaid (← evalAs evalCs cs) (← evalAs evalModel m))

/-- `#sysml_svg m "path.svg"`: render the model graph to SVG via `dot`. -/
elab "#sysml_svg" id:ident path:str : command => do
  renderSvg (Model.toDot (← evalAs evalModel id)) path.getString

/-- `#stpa_svg cs m "path.svg"`: render the control structure to SVG. -/
elab "#stpa_svg" cs:ident m:ident path:str : command => do
  renderSvg (ControlStructure.toDot (← evalAs evalCs cs) (← evalAs evalModel m))
    path.getString

end Sysml.Viz
