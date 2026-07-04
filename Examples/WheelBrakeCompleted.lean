import Examples.WheelBrake

/-!
# Riff: the wheel-brake system, completed

`Examples.WheelBrake` transcribes the STPA Handbook's wheel-brake case
study faithfully — including its self-declared incompleteness, which the
checker measures as exactly 17 findings (`WheelBrake.wbs_gaps`). This file
answers the natural follow-up: what would it take to close those 17 gaps?

Everything reused from `WheelBrake` (model, control structure, losses,
hazards, the six published UCAs and their requirements/scenarios) is the
handbook's own material. Everything *added* below is OUR engineering
judgment, not the handbook's — each addition is marked "(ours)" in its
description and called out in the comments.
-/

namespace Examples.WheelBrakeCompleted

open Sysml Sysml.Kernel Sysml.Stpa

/-- SC-6.4 and SC-6.6 (ours) close the two `hazard-unconstrained` findings
on H-4.4 and H-4.6. -/
def constraints : List SystemConstraint :=
  WheelBrake.constraints ++ [
    { id := 64, desc := "SC-6.4 (ours): Acceleration must not be applied while taxiing above TBD speed", hazards := [44] },
    { id := 66, desc := "SC-6.6 (ours): Takeoff acceleration must reach TBD threshold or takeoff must be rejected", hazards := [46] }
  ]

/-- C-7 (ours) closes the `uca-orphaned` finding on UCA7 (Crew-UCA-1). -/
def requirements : List Requirement :=
  WheelBrake.requirements ++ [
    { id := 7, desc := "C-7 (ours): the crew must power off the BSCU upon a persistent fault indication", ucas := [7] }
  ]

/-- Three scenarios (ours) close the `uca-no-scenario` findings on UCA4,
UCA5, UCA6. -/
def scenarios : List Scenario :=
  WheelBrake.scenarios ++ [
    ⟨6, 4, "Scenario (ours) for UCA-4: anti-skid logic prematurely reports taxi speed has been reached, so the BSCU stops commanding braking well before the aircraft has actually slowed"⟩,
    ⟨7, 5, "Scenario (ours) for UCA-5: a brake-wear compensation model underestimates the hydraulic pressure required for the commanded deceleration, so the BSCU applies insufficient braking"⟩,
    ⟨8, 6, "Scenario (ours) for UCA-6: an asymmetric hydraulic line failure delivers full pressure to one set of wheels and degraded pressure to the other, producing directional braking"⟩
  ]

/-- Dispositions (ours) for the 11 `uca-coverage-gap` cells: the completion
does not add UCAs for these cells, it justifies why none are needed. -/
def notApplicable : List (ElementId × UcaKind × String) :=
  let brakePressureId := WheelBrake.wbsModel.idOf "brakePressure"
  let manualBrakeId := WheelBrake.wbsModel.idOf "manualBrake"
  let bscuPowerId := WheelBrake.wbsModel.idOf "bscuPower"
  (UcaKind.all.map fun k =>
    (brakePressureId, k, "physical delivery path; unsafe behavior analyzed on brakeCmd (ours)"))
  ++ (UcaKind.all.map fun k =>
    (manualBrakeId, k, "manual reversion channel; analyzed in the crew-level analysis, not transcribed here (ours)"))
  ++ [
    (bscuPowerId, .providing, "power-off is fail-safe in this abstraction; providing disposed by design (ours)"),
    (bscuPowerId, .wrongTiming, "power-off is fail-safe in this abstraction; timing disposed by design (ours)"),
    (bscuPowerId, .wrongDuration, "power-off is fail-safe in this abstraction; duration disposed by design (ours)")
  ]

/-- The completed analysis: the handbook's own artifacts plus our closures
for every one of the 17 pinned gaps. Certified total below. -/
def analysis : Analysis where
  model := WheelBrake.wbsModel
  cs := WheelBrake.cs
  losses := WheelBrake.losses
  hazards := WheelBrake.hazards
  constraints := constraints
  ucas := WheelBrake.ucas
  notApplicable := notApplicable
  requirements := requirements
  scenarios := scenarios

/-! ## Certificates -/

/-- The completed analysis is fully well-formed: model, control structure,
and STPA document (traceable, covered, total). -/
theorem analysis_wellFormed : analysis.wellFormed = true := by decide

/-- The completed analysis is well-typed in the STPA type system
(docs/stpa-typesystem.pdf): every gap `WheelBrake.wbs_gaps` pinned in the
published tables is closed here. -/
theorem analysis_wellTyped : WellTyped analysis := by decide

end Examples.WheelBrakeCompleted
