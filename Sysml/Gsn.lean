import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# GSN export: the artifact chain as an assurance-case skeleton

Renders an `Analysis` as a Goal Structuring Notation diagram (graphviz DOT):

- a root goal (*system acceptably safe*) supported by one goal per loss;
- loss goals supported by hazard-elimination goals (via hazard→loss traces);
- hazard goals supported by system-constraint goals and UCA-negation goals;
- UCA goals supported by controller-requirement goals;
- loss scenarios attached to their UCA goals as context (dashed);
- one context node recording the Lean certificate status.

Honesty note: this is an assurance-case *skeleton*. The Lean certificate
evidences the argument's structure — traceability, coverage, and totality of
the analysis document (`WellTyped`) — not the satisfaction of the leaf
requirements. Requirement goals are therefore rendered *undeveloped*
(dashed, per GSN convention) until evidence (tests, proofs about behavior)
is attached in a later sprint.

GSN shape conventions approximated in DOT: goals = boxes, context = rounded
boxes with dashed connectors, undeveloped goals = dashed boxes.
-/

namespace Sysml.Stpa

open Sysml.Kernel

private def gsnQuote (s : String) : String :=
  "\"" ++ (s.replace "\"" "\\\"") ++ "\""

/-- Wrap text crudely for node labels (DOT `\n` every ~`w` chars, breaking
at spaces). -/
private def wrap (s : String) (w : Nat := 28) : String :=
  let words := s.splitOn " "
  let (lines, last) := words.foldl (init := ([], "")) fun (acc, cur) word =>
    if cur.isEmpty then (acc, word)
    else if cur.length + 1 + word.length > w then (acc ++ [cur], word)
    else (acc, cur ++ " " ++ word)
  String.intercalate "\\n" (lines ++ [last])

/-- The analysis as a GSN assurance-case skeleton in graphviz DOT. -/
def Analysis.toGsnDot (a : Analysis) (title : String := "system") : String :=
  let node (id label : String) (extra : String := "") : String :=
    s!"  {id} [label={gsnQuote label}{extra}];\n"
  let goal (id : String) (text : String) : String :=
    node id s!"{id}\\n{wrap text}"
  let undeveloped (id : String) (text : String) : String :=
    node id s!"{id}\\n{wrap text}\\n(undeveloped)" ", style=dashed"
  let context (id : String) (text : String) : String :=
    node id (wrap text) ", style=rounded, color=gray40, fontcolor=gray25"
  let edge (p c : String) : String := s!"  {p} -> {c};\n"
  let ctxEdge (p c : String) : String := s!"  {p} -> {c} [style=dashed, arrowhead=empty];\n"
  let root := goal "G0" s!"{title} is acceptably safe"
  let cert := context "Ctx0"
    s!"STPA document well-typed (Lean decide certificate): {a.docWellFormed}"
  let lossGoals := a.losses.map fun l =>
    goal s!"G_L{l.id}" s!"Loss is prevented: {l.desc}"
  let hazardGoals := a.hazards.map fun h =>
    goal s!"G_H{h.id}" s!"Hazard eliminated or mitigated: {h.desc}"
  let scGoals := a.constraints.map fun c =>
    goal s!"G_SC{c.id}" s!"Constraint enforced: {c.desc}"
  let ucaGoals := a.ucas.map fun u =>
    goal s!"G_UCA{u.id}" s!"UCA does not occur: {a.model.nameOf u.action} {u.kind.label} when {u.context}"
  let reqGoals := a.requirements.map fun r =>
    undeveloped s!"G_R{r.id}" s!"Requirement satisfied: {r.desc}"
  let scenarioCtx := a.scenarios.map fun s =>
    context s!"Ctx_S{s.id}" s!"Scenario: {s.desc}"
  let rootEdges := a.losses.map fun l => edge "G0" s!"G_L{l.id}"
  let hazardEdges := a.hazards.flatMap fun h =>
    h.losses.map fun l => edge s!"G_L{l}" s!"G_H{h.id}"
  let scEdges := a.constraints.flatMap fun c =>
    c.hazards.map fun h => edge s!"G_H{h}" s!"G_SC{c.id}"
  let ucaEdges := a.ucas.flatMap fun u =>
    u.hazards.map fun h => edge s!"G_H{h}" s!"G_UCA{u.id}"
  let reqEdges := a.requirements.flatMap fun r =>
    r.ucas.map fun u => edge s!"G_UCA{u}" s!"G_R{r.id}"
  let scenarioEdges := a.scenarios.map fun s =>
    ctxEdge s!"G_UCA{s.uca}" s!"Ctx_S{s.id}"
  "digraph gsn {\n  rankdir=TB;\n  node [shape=box, fontname=\"sans-serif\", fontsize=10];\n  edge [fontname=\"sans-serif\", fontsize=9];\n"
    ++ root ++ cert ++ ctxEdge "G0" "Ctx0"
    ++ String.join lossGoals ++ String.join hazardGoals ++ String.join scGoals
    ++ String.join ucaGoals ++ String.join reqGoals ++ String.join scenarioCtx
    ++ String.join rootEdges ++ String.join hazardEdges ++ String.join scEdges
    ++ String.join ucaEdges ++ String.join reqEdges ++ String.join scenarioEdges
    ++ "}\n"

end Sysml.Stpa
