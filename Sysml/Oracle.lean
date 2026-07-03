import Sysml.Kernel.Render

/-!
# Second-source oracle: validating emitter output

Round-trip validation of `Model.render` output against an independent
SysML v2 parser — the MontiCore second-source parser (`MCSysMLv2.jar`,
https://github.com/MontiCore/sysmlv2), which is purpose-built for comparison
with the OMG pilot implementation. Its parser is a strong *syntax* oracle
(validated against the official SST example models); its semantic checks are
incomplete, but semantics on our side are already covered by the decidable
well-formedness certificates.

Tool quirks encoded here:
- the jar exits 0 even on parse errors, reporting them as `[ERROR]` lines on
  stdout — so we grep the output instead of trusting the exit code;
- dangling references produce only `[WARN]`, which we surface but don't fail.
-/

namespace Sysml.Oracle

open Sysml.Kernel

/-- Default jar location (gitignored; download from
https://www.monticore.de/download/MCSysMLv2.jar). -/
def defaultJar : System.FilePath := "vendor" / "MCSysMLv2.jar"

/-- Resolve the oracle jar: explicit path → `MCSYSML_JAR` env var → the
`vendor/` default. `none` if nothing is found. -/
def resolveJar (explicit : Option String := none) : IO (Option System.FilePath) := do
  if let some p := explicit then
    return some p
  if let some p := (← IO.getEnv "MCSYSML_JAR") then
    return some p
  if (← defaultJar.pathExists) then
    return some defaultJar
  return none

/-- Is a `java` runtime on the PATH? -/
def javaAvailable : IO Bool := do
  try
    let out ← IO.Process.output { cmd := "java", args := #["-version"] }
    return out.exitCode == 0
  catch _ =>
    return false

/-- Outcome of one oracle run. -/
structure Verdict where
  ok : Bool
  /-- Full tool output (errors when `!ok`; possibly warnings when `ok`). -/
  output : String

/-- Validate SysML v2 source text with the oracle parser. -/
def validateText (jar : System.FilePath) (name : String) (source : String) :
    IO Verdict := do
  IO.FS.withTempDir fun dir => do
    let file := dir / s!"{name}.sysml"
    IO.FS.writeFile file source
    let out ← IO.Process.output
      { cmd := "java", args := #["-jar", jar.toString, "-i", file.toString] }
    let combined := out.stdout ++ out.stderr
    let failed := out.exitCode != 0 || (combined.splitOn "[ERROR]").length > 1
    return { ok := !failed, output := combined.trim }

/-- Render a model with our emitter and validate the result. -/
def validateModel (jar : System.FilePath) (name : String) (m : Model) :
    IO Verdict :=
  validateText jar name m.render

end Sysml.Oracle
