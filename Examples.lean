-- Root of the `Examples` library: worked SysML/STPA models plus a registry
-- the CLI (`Cli.lean`) renders from.
import Examples.InsulinPump

namespace Examples

open Sysml.Kernel Sysml.Stpa

/-- A registered example: a model, optionally with an STPA control structure
and full analysis. -/
structure Entry where
  name : String
  descr : String
  model : Model
  cs : Option ControlStructure := none
  analysis : Option Analysis := none

/-- All examples known to the CLI. -/
def registry : List Entry := [
  { name := "insulin-pump",
    descr := "closed-loop insulin infusion pump with a full STPA analysis",
    model := InsulinPump.pumpModel,
    cs := some InsulinPump.pumpCs,
    analysis := some InsulinPump.analysis }
]

def find? (name : String) : Option Entry :=
  registry.find? (·.name = name)

end Examples
