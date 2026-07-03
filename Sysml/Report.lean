import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# Markdown STPA reports

Renders an `Analysis` as a markdown document — losses, hazards, and the UCA
table — for READMEs, writeups, and the CLI's `report` format.
-/

namespace Sysml.Stpa

open Sysml.Kernel

private def harmLabel : HarmKind → String
  | .safety => "safety"
  | .security => "security"

private def ucaLabel : UcaKind → String
  | .notProviding => "not providing"
  | .providing => "providing"
  | .wrongTiming => "too early / too late / out of order"
  | .wrongDuration => "stopped too soon / applied too long"

private def natList (ns : List Nat) (prefixStr : String) : String :=
  String.intercalate ", " (ns.map fun n => s!"{prefixStr}{n}")

/-- Render the analysis as a markdown report. -/
def Analysis.toMarkdown (a : Analysis) (title : String := "STPA report") : String :=
  let losses := a.losses.map fun l =>
    s!"| L{l.id} | {l.desc} |\n"
  let hazards := a.hazards.map fun h =>
    s!"| H{h.id} | {harmLabel h.kind} | {h.desc} | {natList h.losses "L"} |\n"
  let ucas := a.ucas.map fun u =>
    s!"| UCA{u.id} | {a.model.nameOf u.action} | {ucaLabel u.kind} | {u.context} | {natList u.hazards "H"} |\n"
  let nas := a.notApplicable.map fun (c, k, why) =>
    s!"| — | {a.model.nameOf c} | {ucaLabel k} | N/A: {why} | — |\n"
  s!"# {title}\n\n"
    ++ "## Losses\n\n| id | description |\n|---|---|\n"
    ++ String.join losses
    ++ "\n## Hazards\n\n| id | kind | description | losses |\n|---|---|---|---|\n"
    ++ String.join hazards
    ++ "\n## Unsafe control actions\n\n| id | control action | type | context | hazards |\n|---|---|---|---|---|\n"
    ++ String.join ucas ++ String.join nas
    ++ s!"\n## Verification\n\n- analysis well-formed (traceable + UCA-complete): `{a.wellFormed}`\n"

end Sysml.Stpa
