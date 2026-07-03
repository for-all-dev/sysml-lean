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
  sysml check <example>
      Run the decidable well-formedness checks (model, control structure,
      STPA analysis). Exit code 1 if any fail.
  sysml render <example> [--format FMT] [--stpa] [-o FILE]
      Render an example. FMT is one of:
        sysml    SysML v2 textual notation (default)
        dot      graphviz DOT
        mermaid  Mermaid flowchart (GitHub-renderable)
        svg      SVG via graphviz `dot` (requires -o FILE)
        report   markdown STPA report (requires the example to have an analysis)
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
  | f => throw (IO.userError s!"unknown format '{f}' (sysml|dot|mermaid|svg|report)")
  return 0

def runCheck (name : String) : IO UInt32 := do
  let e ← getEntry name
  let mut failed := false
  let report (what : String) (ok : Bool) : IO Unit :=
    IO.println s!"{if ok then "✓" else "✗"} {what}"
  let mOk := e.model.wellFormed
  report "model well-formed" mOk
  failed := failed || !mOk
  if let some cs := e.cs then
    let csOk := cs.wellFormed e.model
    report "control structure well-formed (closed loops)" csOk
    failed := failed || !csOk
  if let some a := e.analysis then
    let aOk := a.hazardsTraceable && a.ucasTraceable && a.ucasCover
    report "STPA analysis traceable and UCA-complete" aOk
    failed := failed || !aOk
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
    | ["check", name] => runCheck name
    | "render" :: name :: rest => runRender name rest
    | [] | ["--help"] | ["-h"] | ["help"] => IO.println usage; return (0 : UInt32)
    | _ => IO.eprintln usage; return (2 : UInt32)
  catch e =>
    IO.eprintln s!"error: {e.toString}"
    return (1 : UInt32)
