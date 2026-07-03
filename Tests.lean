import Sysml
import Examples

/-!
# Test driver (`lake test`)

The positive certificates are compile-time theorems in `Examples`; this
driver covers what theorems can't: *negative* cases (broken models must be
rejected — guarding against vacuous well-formedness checks) and smoke tests
of the renderers.
-/

open Sysml.Kernel Sysml.Stpa Sysml.View
open Examples.InsulinPump

def checks : List (String × Bool) :=
  -- positives (mirrors the theorems; cheap sanity that the exe agrees)
  [ ("model well-formed", pumpModel.wellFormed),
    ("control structure well-formed", pumpCs.wellFormed pumpModel),
    ("analysis well-formed", analysis.wellFormed),
    -- negatives: each broken variant must be rejected
    ("open control loop detected",
      let openLoop : ControlStructure := { pumpCs with feedbackPaths := [pumpModel.idOf "glucoseFlow"] }
      !openLoop.controlLoopsClosed pumpModel),
    ("reversed flow direction detected",
      let ins := pumpModel.idOf "insulinFlow"
      let out := pumpModel.idOf "insulinOut"
      let inp := pumpModel.idOf "insulinIn"
      let bad : Model := { pumpModel with rels := pumpModel.rels.map fun (r : Relationship) =>
        if (r.kind = RelKind.connectorEnd 0 ∧ r.source = ins) then { r with target := inp }
        else if (r.kind = RelKind.connectorEnd 1 ∧ r.source = ins) then { r with target := out }
        else r }
      !bad.flowsDirected && !bad.wellFormed),
    ("duplicate ids detected",
      let bad : Model := { pumpModel with elements := pumpModel.elements ++ pumpModel.elements.take 1 }
      !bad.uniqueIds),
    ("dangling owner detected",
      let bad : Model := { pumpModel with elements :=
        pumpModel.elements ++ [{ id := ⟨999⟩, kind := .partDef, owner := some ⟨998⟩ }] }
      !bad.ownersWellFounded),
    ("UCA coverage gap detected",
      let gappy : Analysis := { analysis with ucas := analysis.ucas.drop 1 }
      !gappy.ucasCover),
    ("untraceable hazard detected",
      let bad : Analysis := { analysis with hazards := analysis.hazards ++ [{ id := 9, desc := "orphan", losses := [42] }] }
      !bad.hazardsTraceable),
    -- renderer smoke tests
    ("sysml render round-trips key syntax",
      let r := pumpModel.render
      (r.splitOn "part pumpController : Controller {").length == 2
      && (r.splitOn "flow deliverCmd of InsulinCommand from pumpController.cmdOut to pumpMotor.cmdIn;").length == 2),
    ("dot output shaped correctly",
      let d := pumpCs.toDot pumpModel
      (d.splitOn "digraph").length == 2 && (d.splitOn "style=dashed").length == 3),
    ("mermaid output shaped correctly",
      let mm := pumpCs.toMermaid pumpModel
      (mm.splitOn "flowchart TB").length == 2 && (mm.splitOn "-.->").length == 3),
    ("markdown report contains UCA table",
      ((analysis.toMarkdown).splitOn "| UCA").length == 5),
    -- view-layer behavior
    ("part-level links recovered",
      (links pumpModel).length == 4),
    ("reachability: controller reaches process via control edges",
      reachable (pumpCs.controlEdges pumpModel)
        (pumpModel.idOf "pumpController") (pumpModel.idOf "patient")),
    ("reachability: not backwards",
      !reachable (pumpCs.controlEdges pumpModel)
        (pumpModel.idOf "patient") (pumpModel.idOf "pumpController")) ]

def main : IO UInt32 := do
  let mut failures := 0
  for (name, ok) in checks do
    IO.println s!"{if ok then "✓" else "✗"} {name}"
    if !ok then failures := failures + 1
  if failures == 0 then
    IO.println s!"all {checks.length} tests passed"
    return 0
  else
    IO.eprintln s!"{failures} of {checks.length} tests failed"
    return 1
