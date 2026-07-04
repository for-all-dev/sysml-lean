import Examples.WheelBrakeCompleted

/-!
# Riff: wheel-brake, STPA-Sec extension

STPA-Sec (Young & Leveson, 2014) treats security as a special case of
safety: adversarial action is just another way to reach a hazardous
control state, so the same STPA machinery applies once hazards are
allowed to carry a `security` tag (`Sysml.Stpa.HarmKind`).

This file extends `Examples.WheelBrakeCompleted` (not the raw handbook
transcription) with two security hazards on the wheel-speed feedback and
brake command channels, so the result stays a *total*, well-typed
analysis throughout. Everything here is OUR addition (ours), riffing on
the handbook's model rather than transcribing it.
-/

namespace Examples.WheelBrakeSec

open Sysml Sysml.Kernel Sysml.Stpa

/-- Two adversarial (security) hazards (ours), extending the completed
hazard list. -/
def hazards : List Hazard :=
  WheelBrake.hazards ++ [
    { id := 47, desc := "H-4.7 (ours, security): BSCU acts on spoofed or replayed wheel-speed feedback",
      kind := .security, losses := [1, 2, 5] },
    { id := 48, desc := "H-4.8 (ours, security): braking commands accepted from a source other than the BSCU or crew",
      kind := .security, losses := [1, 2, 5] }
  ]

/-- Security constraints (ours) addressing the two security hazards. -/
def constraints : List SystemConstraint :=
  WheelBrakeCompleted.constraints ++ [
    { id := 67, desc := "SC-6.7 (ours): wheel-speed feedback must be integrity-protected and fresh", hazards := [47] },
    { id := 68, desc := "SC-6.8 (ours): brake actuation must authenticate its commanding channel", hazards := [48] }
  ]

/-- A security UCA (ours): a spoofed feedback signal causing the BSCU to
provide braking after V1 during takeoff. -/
def ucas : List Uca :=
  WheelBrake.ucas ++ [
    { id := 8, action := WheelBrake.wbsModel.idOf "brakeCmd", kind := .providing,
      context := "when wheel-speed feedback has been spoofed to indicate landing roll during takeoff",
      hazards := [47, 43] }
  ]

/-- Requirement (ours) refining the security UCA. -/
def requirements : List Requirement :=
  WheelBrakeCompleted.requirements ++ [
    { id := 8, desc := "C-8 (ours): BSCU must reject wheel-speed readings failing integrity or freshness checks", ucas := [8] }
  ]

/-- Loss scenario (ours) for the security UCA. -/
def scenarios : List Scenario :=
  WheelBrakeCompleted.scenarios ++ [
    ⟨9, 8, "An adversary replays recorded landing-roll wheel-speed frames during takeoff; the BSCU's process model shows landing roll and it commands braking after V1"⟩
  ]

/-- The STPA-Sec analysis: the completed analysis plus the adversarial
extension. Certified total below. -/
def analysis : Analysis where
  model := WheelBrake.wbsModel
  cs := WheelBrake.cs
  losses := WheelBrake.losses
  hazards := hazards
  constraints := constraints
  ucas := ucas
  notApplicable := WheelBrakeCompleted.notApplicable
  requirements := requirements
  scenarios := scenarios

/-! ## Certificates -/

/-- The STPA-Sec extension remains fully well-formed. -/
theorem analysis_wellFormed : analysis.wellFormed = true := by decide

/-- The STPA-Sec extension remains well-typed (docs/stpa-typesystem.pdf). -/
theorem analysis_wellTyped : WellTyped analysis := by decide

/-- The two security-framed hazards (H-4.7, H-4.8) are present. -/
theorem two_security_hazards :
    (analysis.hazards.filter (·.kind = Sysml.Stpa.HarmKind.security)).length = 2 := by decide

end Examples.WheelBrakeSec
