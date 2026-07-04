import Sysml.Stpa
import Sysml.Kernel.Render

/-!
# SACM export: the GSN argument skeleton as OMG SACM XMI

OMG's **Structured Assurance Case Metamodel** (SACM, current line 2.1/2.2) is
the standards-track metamodel behind both GSN and CAE assurance-case
notations; its Argumentation package defines `Claim`/`ArgumentReasoning`
(`AssertedInference`)/`ArtifactReference` elements exchanged as XMI
(docs/interop.agents.md §5). Two independent commercial tools are confirmed
to import/export it: Adelard **ASCE** (dedicated SACM export plugin) and
**Astah System Safety** (though Astah's own docs cite "SACM 1.0" while OMG's
current spec line is 2.x — a version-naming mismatch we haven't resolved).
That makes SACM XML the highest-confidence assurance-case interop surface
available to us, ahead of GSN's own tool-specific formats.

This emitter is the standards-track sibling of `Sysml.Stpa.Analysis.toGsnDot`
(`Sysml/Gsn.lean`): it walks the *same* GSN-shaped argument built from an
`Analysis` — root goal → losses → hazards → constraints/UCA-negations →
requirements, with scenarios and the Lean certificate as context — and emits
it as SACM `Claim` / `AssertedInference` / `ArtifactReference` /
`AssertedContext` elements instead of graphviz boxes.

Caveats (honesty, matching `Gsn.lean`'s convention):

- The XMI namespace URI used here (`http://www.omg.org/spec/SACM/20210201/SACM.xmi`)
  is best-effort against the SACM 2.2 spec; we have not round-tripped the
  output through a real SACM-consuming tool (Astah / ASCE import). That
  verification is unverified and tracked as follow-up.
- As in the GSN export, requirement claims are marked `toBeSupported="true"`
  (SACM's counterpart to GSN's "undeveloped" marker): the Lean certificate
  evidences the *argument's structure* (traceability, coverage, totality of
  the STPA document), not the satisfaction of leaf requirements.
-/

namespace Sysml.Stpa

open Sysml.Kernel

/-- XML-escape the five predefined XML entities. -/
private def xmlEscape (s : String) : String :=
  ((((s.replace "&" "&amp;").replace "<" "&lt;").replace ">" "&gt;")
    |>.replace "\"" "&quot;")
    |>.replace "'" "&apos;"

/-- A self-closing `<argumentationElement>` (or nested-element) tag with the
given `xmi:type` and attributes. -/
private def selfClosing (xmiType : String) (attrs : List (String × String)) : String :=
  let attrStr := String.join (attrs.map fun (k, v) => s!" {k}={xmlEscape v |> ("\"" ++ · ++ "\"")}")
  s!"  <argumentationElement xmi:type=\"{xmiType}\"{attrStr}/>\n"

/-- A `Claim` element carrying a `<description>` child, optionally marked
`toBeSupported` (SACM's undeveloped-goal marker). -/
private def claim (id text : String) (toBeSupported : Bool := false) : String :=
  let tbs := if toBeSupported then " toBeSupported=\"true\"" else ""
  s!"  <argumentationElement xmi:type=\"Claim\" xmi:id=\"{id}\"{tbs}>\n"
    ++ s!"    <description><content lang=\"en\" content=\"{xmlEscape text}\"/></description>\n"
    ++ "  </argumentationElement>\n"

/-- An `ArtifactReference` element carrying a `<description>` child. -/
private def artifactReference (id text : String) : String :=
  s!"  <argumentationElement xmi:type=\"ArtifactReference\" xmi:id=\"{id}\">\n"
    ++ s!"    <description><content lang=\"en\" content=\"{xmlEscape text}\"/></description>\n"
    ++ "  </argumentationElement>\n"

/-- An `AssertedInference` edge: `premise` supports the `reasoned` claim. -/
private def assertedInference (reasoned premise : String) : String :=
  selfClosing "AssertedInference" [("reasoned", s!"#{reasoned}"), ("premise", s!"#{premise}")]

/-- An `AssertedContext` edge: `context` (an artifact) is attached as context
to the `reasoned` claim. -/
private def assertedContext (reasoned context : String) : String :=
  selfClosing "AssertedContext" [("reasoned", s!"#{reasoned}"), ("context", s!"#{context}")]

/-- The analysis as a SACM 2.2 XMI `ArgumentPackage`. Mirrors
`Analysis.toGsnDot`'s argument structure exactly, from the same data:

- root claim `G0` ("{title} is acceptably safe"), supported by one claim per
  loss;
- loss claims supported by hazard claims (via hazard→loss traces);
- hazard claims supported by system-constraint claims and UCA-negation
  claims;
- UCA claims supported by controller-requirement claims (marked
  `toBeSupported`, undeveloped);
- loss scenarios attached to their UCA claims as `ArtifactReference` +
  `AssertedContext`;
- the Lean certificate attached to the root claim the same way. -/
def Analysis.toSacmXml (a : Analysis) (title : String := "assurance case") : String :=
  let rootClaim := claim "G0" s!"{title} is acceptably safe"
  let certArtifact := artifactReference "Cert0"
    s!"STPA document well-typed (Lean decide certificate): {a.docWellFormed}"
  let certContext := assertedContext "G0" "Cert0"
  let lossClaims := a.losses.map fun l =>
    claim s!"G_L{l.id}" s!"Loss is prevented: {l.desc}"
  let hazardClaims := a.hazards.map fun h =>
    claim s!"G_H{h.id}" s!"Hazard eliminated or mitigated: {h.desc}"
  let scClaims := a.constraints.map fun c =>
    claim s!"G_SC{c.id}" s!"Constraint enforced: {c.desc}"
  let ucaClaims := a.ucas.map fun u =>
    claim s!"G_UCA{u.id}"
      s!"UCA does not occur: {a.model.nameOf u.action} {u.kind.label} when {u.context}"
  let reqClaims := a.requirements.map fun r =>
    claim s!"G_R{r.id}" s!"Requirement satisfied: {r.desc}" true
  let scenarioArtifacts := a.scenarios.map fun s =>
    artifactReference s!"S{s.id}" s.desc
  let rootEdges := a.losses.map fun l => assertedInference "G0" s!"G_L{l.id}"
  let hazardEdges := a.hazards.flatMap fun h =>
    h.losses.map fun l => assertedInference s!"G_L{l}" s!"G_H{h.id}"
  let scEdges := a.constraints.flatMap fun c =>
    c.hazards.map fun h => assertedInference s!"G_H{h}" s!"G_SC{c.id}"
  let ucaEdges := a.ucas.flatMap fun u =>
    u.hazards.map fun h => assertedInference s!"G_H{h}" s!"G_UCA{u.id}"
  let reqEdges := a.requirements.flatMap fun r =>
    r.ucas.map fun u => assertedInference s!"G_UCA{u}" s!"G_R{r.id}"
  let scenarioEdges := a.scenarios.map fun s =>
    assertedContext s!"G_UCA{s.uca}" s!"S{s.id}"
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    ++ "<ArgumentPackage xmlns:xmi=\"http://www.omg.org/spec/XMI/20131001\" "
    ++ "xmlns=\"http://www.omg.org/spec/SACM/20210201/SACM.xmi\" "
    ++ s!"xmi:version=\"2.0\" xmi:id=\"AP0\" name=\"{xmlEscape title}\">\n"
    ++ rootClaim ++ certArtifact ++ certContext
    ++ String.join lossClaims ++ String.join hazardClaims ++ String.join scClaims
    ++ String.join ucaClaims ++ String.join reqClaims ++ String.join scenarioArtifacts
    ++ String.join rootEdges ++ String.join hazardEdges ++ String.join scEdges
    ++ String.join ucaEdges ++ String.join reqEdges ++ String.join scenarioEdges
    ++ "</ArgumentPackage>\n"

end Sysml.Stpa
