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

/-- Render the analysis as a markdown report: the full artifact chain
losses → hazards → system constraints → UCAs → controller requirements →
loss scenarios, with traceability columns throughout. -/
def Analysis.toMarkdown (a : Analysis) (title : String := "STPA report") : String :=
  let losses := a.losses.map fun l =>
    s!"| L{l.id} | {l.desc} |\n"
  let hazards := a.hazards.map fun h =>
    s!"| H{h.id} | {harmLabel h.kind} | {h.desc} | {natList h.losses "L"} |\n"
  let constraints := a.constraints.map fun c =>
    s!"| SC{c.id} | {c.desc} | {natList c.hazards "H"} |\n"
  let ucas := a.ucas.map fun u =>
    s!"| UCA{u.id} | {a.model.nameOf u.action} | {ucaLabel u.kind} | {u.context} | {natList u.hazards "H"} |\n"
  let nas := a.notApplicable.map fun (c, k, why) =>
    s!"| — | {a.model.nameOf c} | {ucaLabel k} | N/A: {why} | — |\n"
  let reqs := a.requirements.map fun r =>
    s!"| R{r.id} | {r.desc} | {natList r.ucas "UCA"} |\n"
  let scenarios := a.scenarios.map fun s =>
    s!"| S{s.id} | UCA{s.uca} | {s.desc} |\n"
  s!"# {title}\n\n"
    ++ "## Losses\n\n| id | description |\n|---|---|\n"
    ++ String.join losses
    ++ "\n## Hazards\n\n| id | kind | description | losses |\n|---|---|---|---|\n"
    ++ String.join hazards
    ++ "\n## System-level constraints\n\n| id | constraint | hazards |\n|---|---|---|\n"
    ++ String.join constraints
    ++ "\n## Unsafe control actions\n\n| id | control action | type | context | hazards |\n|---|---|---|---|---|\n"
    ++ String.join ucas ++ String.join nas
    ++ "\n## Controller requirements\n\n| id | requirement | refines |\n|---|---|---|\n"
    ++ String.join reqs
    ++ "\n## Loss scenarios\n\n| id | uca | scenario |\n|---|---|---|\n"
    ++ String.join scenarios
    ++ "\n## Verification\n\n"
    ++ s!"- document well-typed (traceable, covered, no orphaned UCAs): `{a.docWellFormed}`\n"
    ++ s!"- analysis well-formed (incl. model + control structure): `{a.wellFormed}`\n"
    ++ s!"- loss-scenario coverage (step 4, optional): `{a.scenariosCover}`\n"

end Sysml.Stpa
