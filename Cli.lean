import Sysml
import Examples

/-!
# `sysml` CLI

Renders registered examples (`Examples.registry`) in the formats the library
supports. Argument parsing is hand-rolled (the community `lean4-cli` package
was considered, but its root module is named `Cli`, which collides with this
file; the surface here is small enough not to warrant a dependency).

```
sysml list
sysml check <example>
sysml render <example> [--format sysml|dot|mermaid|svg|report] [--stpa] [-o FILE]
```
-/

open Sysml.Kernel Sysml.Stpa Sysml.Viz

def usage : String :=
"sysml — SysML v2 + STPA in Lean

USAGE:
  sysml list
      List registered examples.
  sysml check [<example>] [--json]
      Run the checker and report findings (broken traces, coverage gaps,
      orphaned UCAs, authority cycles, open loops …). All registered
      examples when no name is given. --json emits machine-readable
      verdicts for tooling/CI. Exit 1 on any error-severity finding.
  sysml diff <old.json> <new.json> [--markdown]
      Compare two `check --json` verdict files; report findings introduced
      and fixed (identity = check × subject). --markdown shapes the output
      for a PR comment. Exit 1 if any error finding was introduced.
  sysml validate [<example>] [--jar PATH]
      Round-trip the SysML emitter output through the MontiCore
      second-source parser (MCSysMLv2.jar). Validates all registered
      examples when no name is given. The jar is found via --jar, the
      MCSYSML_JAR env var, or vendor/MCSysMLv2.jar; download it from
      https://www.monticore.de/download/MCSysMLv2.jar. Exit 1 on any
      parse error.
  sysml render <example> [--format FMT] [--stpa] [-o FILE]
      Render an example. FMT is one of:
        sysml    SysML v2 textual notation (default)
        dot      graphviz DOT
        mermaid  Mermaid flowchart (GitHub-renderable)
        svg      SVG via graphviz `dot` (requires -o FILE)
        report   markdown STPA report (requires the example to have an analysis)
        gsn      GSN assurance-case skeleton as graphviz DOT
        gsn-svg  GSN skeleton as SVG via `dot` (requires -o FILE)
      --stpa renders the STPA control structure (roles, control/feedback
      edges) instead of the plain part-connection graph; applies to
      dot/mermaid/svg.
  Output goes to stdout unless -o FILE is given."

structure RenderOpts where
  format : String := "sysml"
  stpa : Bool := false
  out : Option String := none

private def parseRenderOpts : List String → Except String RenderOpts → Except String RenderOpts
  | [], acc => acc
  | "--format" :: f :: rest, .ok o => parseRenderOpts rest (.ok { o with format := f })
  | "--stpa" :: rest, .ok o => parseRenderOpts rest (.ok { o with stpa := true })
  | "-o" :: f :: rest, .ok o => parseRenderOpts rest (.ok { o with out := some f })
  | "--output" :: f :: rest, .ok o => parseRenderOpts rest (.ok { o with out := some f })
  | arg :: _, .ok _ => .error s!"unexpected argument '{arg}'"
  | _, .error e => .error e

private def emit (o : RenderOpts) (s : String) : IO Unit :=
  match o.out with
  | some path => IO.FS.writeFile path s
  | none => IO.print s

private def getEntry (name : String) : IO Examples.Entry := do
  match Examples.find? name with
  | some e => return e
  | none =>
    throw (IO.userError
      s!"unknown example '{name}'; try: {String.intercalate ", " (Examples.registry.map (·.name))}")

/-- The DOT source selected by `--stpa`, or an error if no control structure
is registered. -/
private def dotSource (e : Examples.Entry) (stpa : Bool) : IO String :=
  if stpa then
    match e.cs with
    | some cs => return cs.toDot e.model
    | none => throw (IO.userError s!"example '{e.name}' has no control structure")
  else
    return e.model.toDot

private def mermaidSource (e : Examples.Entry) (stpa : Bool) : IO String :=
  if stpa then
    match e.cs with
    | some cs => return cs.toMermaid e.model
    | none => throw (IO.userError s!"example '{e.name}' has no control structure")
  else
    return e.model.toMermaid

def runRender (name : String) (args : List String) : IO UInt32 := do
  let o ← IO.ofExcept ((parseRenderOpts args (.ok {})).mapError IO.userError)
  let e ← getEntry name
  match o.format with
  | "sysml" => emit o e.model.render
  | "dot" => emit o (← dotSource e o.stpa)
  | "mermaid" => emit o (← mermaidSource e o.stpa)
  | "svg" =>
    match o.out with
    | some path => dotToSvgFile (← dotSource e o.stpa) path
    | none => throw (IO.userError "svg format requires -o FILE")
  | "report" =>
    match e.analysis with
    | some a => emit o (a.toMarkdown s!"STPA report: {e.name}")
    | none => throw (IO.userError s!"example '{e.name}' has no STPA analysis")
  | "gsn" =>
    match e.analysis with
    | some a => emit o (a.toGsnDot e.name)
    | none => throw (IO.userError s!"example '{e.name}' has no STPA analysis")
  | "gsn-svg" =>
    match e.analysis, o.out with
    | some a, some path => dotToSvgFile (a.toGsnDot e.name) path
    | none, _ => throw (IO.userError s!"example '{e.name}' has no STPA analysis")
    | _, none => throw (IO.userError "gsn-svg format requires -o FILE")
  | f => throw (IO.userError s!"unknown format '{f}' (sysml|dot|mermaid|svg|report|gsn|gsn-svg)")
  return 0

/-- The analysis to check for an entry: the registered one, or a bare
model(-and-control-structure) analysis when none is registered. -/
private def analysisOf (e : Examples.Entry) : Analysis :=
  e.analysis.getD
    { model := e.model, cs := e.cs.getD ⟨[], [], []⟩,
      losses := [], hazards := [], ucas := [] }

private def severityMark : Severity → String
  | .error => "⛔"
  | .warning => "⚠"
  | .info => "ℹ"

open Lean (Json) in
private def findingToJson (f : Finding) : Json :=
  Json.mkObj [
    ("check", Json.str f.check),
    ("severity", Json.str f.severity.label),
    ("subject", Json.str f.subject),
    ("message", Json.str f.message)
  ]

open Lean (Json) in
private def verdictToJson (name : String) (ok : Bool) (fs : List Finding) : Json :=
  Json.mkObj [
    ("name", Json.str name),
    ("ok", Json.bool ok),
    ("findings", Json.arr (fs.map findingToJson).toArray)
  ]

def runCheck (args : List String) : IO UInt32 := do
  let (exName, json) ← IO.ofExcept <| (Except.mapError IO.userError) <|
    match args with
    | [] => .ok (none, false)
    | ["--json"] => .ok (none, true)
    | [n] => .ok (some n, false)
    | [n, "--json"] | ["--json", n] => .ok (some n, true)
    | _ => .error "usage: sysml check [<example>] [--json]"
  let entries ← match exName with
    | some n => do pure [← getEntry n]
    | none => pure Examples.registry
  let mut failed := false
  let mut verdicts : List Lean.Json := []
  for e in entries do
    let fs := (analysisOf e).findings
    let ok := fs.all (·.severity ≠ .error)
    failed := failed || !ok
    if json then
      verdicts := verdicts ++ [verdictToJson e.name ok fs]
    else
      IO.println s!"{if ok then "✓" else "✗"} {e.name}"
      for f in fs do
        IO.println s!"  {severityMark f.severity} [{f.check}] {f.subject}: {f.message}"
  if json then
    IO.println (Lean.Json.arr verdicts.toArray).pretty
  return if failed then (1 : UInt32) else 0

/-! ## `sysml diff`: compare two verdict files -/

private structure DiffVerdict where
  name : String
  ok : Bool
  findings : List Finding

open Lean (Json) in
private def findingOfJson (j : Json) : Except String Finding := do
  let check ← j.getObjValAs? String "check"
  let sev ← j.getObjValAs? String "severity"
  let subject ← j.getObjValAs? String "subject"
  let message ← j.getObjValAs? String "message"
  let severity ← match sev with
    | "error" => pure Severity.error
    | "warning" => pure Severity.warning
    | "info" => pure Severity.info
    | s => throw s!"unknown severity '{s}'"
  return { check, severity, subject, message }

open Lean (Json) in
private def parseVerdicts (path : String) : IO (List DiffVerdict) := do
  let text ← IO.FS.readFile path
  IO.ofExcept <| (Except.mapError fun e => IO.userError s!"{path}: {e}") <| do
    let j ← Json.parse text
    let arr ← j.getArr?
    arr.toList.mapM fun v => do
      let name ← v.getObjValAs? String "name"
      let ok ← v.getObjValAs? Bool "ok"
      let fs ← (← v.getObjVal? "findings").getArr?
      let findings ← fs.toList.mapM findingOfJson
      return { name, ok, findings }

/-- Stable identity of a finding across revisions. -/
private def findingKey (f : Finding) : String × String := (f.check, f.subject)

private def renderFinding (f : Finding) : String :=
  s!"{severityMark f.severity} `{f.check}` **{f.subject}** — {f.message}"

def runDiff (oldPath newPath : String) (markdown : Bool) : IO UInt32 := do
  let old ← parseVerdicts oldPath
  let new ← parseVerdicts newPath
  let names := (old.map (·.name) ++ new.map (·.name)).eraseDups
  let mut introducedErrors := 0
  let mut lines : List String := []
  for n in names do
    let oldFs := ((old.find? (·.name = n)).map (·.findings)).getD []
    let newFs := ((new.find? (·.name = n)).map (·.findings)).getD []
    let introduced := newFs.filter fun f => !oldFs.any (findingKey · = findingKey f)
    let fixed := oldFs.filter fun f => !newFs.any (findingKey · = findingKey f)
    introducedErrors := introducedErrors + (introduced.filter (·.severity = .error)).length
    if introduced.isEmpty && fixed.isEmpty then
      lines := lines ++ [s!"**{n}**: no findings changed"]
    else
      lines := lines ++ [s!"**{n}**:"]
      unless introduced.isEmpty do
        lines := lines ++ [s!"- introduced ({introduced.length}):"]
          ++ introduced.map (fun f => s!"  - {renderFinding f}")
      unless fixed.isEmpty do
        lines := lines ++ [s!"- fixed ({fixed.length}):"]
          ++ fixed.map (fun f => s!"  - {renderFinding f}")
  let header := if markdown then ["### STPA findings diff", ""] else []
  let body := String.intercalate "\n" (header ++ lines)
  IO.println body
  return if introducedErrors > 0 then (1 : UInt32) else 0

private def parseValidateArgs : List String → Except String (Option String × Option String)
  | [] => .ok (none, none)
  | "--jar" :: p :: rest => do
    let (ex, _) ← parseValidateArgs rest
    .ok (ex, some p)
  | arg :: rest =>
    if arg.startsWith "-" then .error s!"unexpected argument '{arg}'"
    else do
      let (_, jar) ← parseValidateArgs rest
      .ok (some arg, jar)

def runValidate (args : List String) : IO UInt32 := do
  let (exName, jarFlag) ← IO.ofExcept ((parseValidateArgs args).mapError IO.userError)
  let entries ← match exName with
    | some n => do pure [← getEntry n]
    | none => pure Examples.registry
  let some jar ← Sysml.Oracle.resolveJar jarFlag
    | throw (IO.userError
        "MCSysMLv2.jar not found: pass --jar PATH, set MCSYSML_JAR, or place it at vendor/MCSysMLv2.jar\n(download: https://www.monticore.de/download/MCSysMLv2.jar)")
  unless (← Sysml.Oracle.javaAvailable) do
    throw (IO.userError "java not found on PATH (a JRE ≥ 21 is required)")
  let mut failed := false
  for e in entries do
    let v ← Sysml.Oracle.validateModel jar e.name e.model
    IO.println s!"{if v.ok then "✓" else "✗"} {e.name} (oracle: MontiCore)"
    if !v.output.isEmpty then
      IO.println v.output
    failed := failed || !v.ok
  return if failed then (1 : UInt32) else 0

def runList : IO UInt32 := do
  for e in Examples.registry do
    let extras := [if e.cs.isSome then some "control structure" else none,
                   if e.analysis.isSome then some "STPA analysis" else none]
    let extras := extras.filterMap id
    let suffix := if extras.isEmpty then "" else s!" [{String.intercalate ", " extras}]"
    IO.println s!"{e.name} — {e.descr}{suffix}"
  return 0

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["list"] => runList
    | "check" :: rest => runCheck rest
    | ["diff", o, n] => runDiff o n false
    | ["diff", o, n, "--markdown"] => runDiff o n true
    | "validate" :: rest => runValidate rest
    | "render" :: name :: rest => runRender name rest
    | [] | ["--help"] | ["-h"] | ["help"] => IO.println usage; return (0 : UInt32)
    | _ => IO.eprintln usage; return (2 : UInt32)
  catch e =>
    IO.eprintln s!"error: {e.toString}"
    return (1 : UInt32)
