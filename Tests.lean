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

/-- Round-trip every registered example through the MontiCore second-source
parser, when java and the jar are available; otherwise skip (keeps `lake
test` dependency-free). Returns (ran, failures). -/
def oracleChecks : IO (Nat × Nat) := do
  let some jar ← Sysml.Oracle.resolveJar
    | IO.println "– oracle round-trip skipped (no vendor/MCSysMLv2.jar or MCSYSML_JAR)"
      return (0, 0)
  unless (← Sysml.Oracle.javaAvailable) do
    IO.println "– oracle round-trip skipped (no java on PATH)"
    return (0, 0)
  let mut failures := 0
  -- negative control: the wrapper must detect the oracle's [ERROR] output
  let broken ← Sysml.Oracle.validateText jar "broken" "package Broken { part def ; }"
  IO.println s!"{if !broken.ok then "✓" else "✗"} oracle rejects broken input"
  if broken.ok then failures := failures + 1
  for e in Examples.registry do
    let v ← Sysml.Oracle.validateModel jar e.name e.model
    IO.println s!"{if v.ok then "✓" else "✗"} oracle round-trip: {e.name}"
    if !v.ok then
      IO.println v.output
      failures := failures + 1
  return (Examples.registry.length + 1, failures)

def main : IO UInt32 := do
  let mut failures := 0
  for (name, ok) in checks do
    IO.println s!"{if ok then "✓" else "✗"} {name}"
    if !ok then failures := failures + 1
  let (oracleRan, oracleFailures) ← oracleChecks
  failures := failures + oracleFailures
  let total := checks.length + oracleRan
  if failures == 0 then
    IO.println s!"all {total} tests passed"
    return 0
  else
    IO.eprintln s!"{failures} of {total} tests failed"
    return 1
