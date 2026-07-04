import Sysml.Dsl
import Sysml.Stpa
import Sysml.Typing
import Sysml.Findings
import Sysml.Viz

/-!
# Worked example: aircraft wheel-brake system (STPA Handbook)

A faithful transcription of the wheel-brake system (WBS) case study from
the STPA Handbook (Leveson & Thomas, 2018), §2 — the textbook worked
example of STPA applied to the Boeing 737 BSCU (Brake System Control Unit)
autobrake function.

The handbook's own tables are **self-declared partial** ("a partial
example", "this is not a complete example" — Table 2.1, 2.3, 2.5 and the
surrounding text). Rather than paper over that, this transcription pins
the *exact* set of findings the checker produces on the published
material, so the gaps in the handbook itself are a certified, reproducible
fact about the source, not an assertion we have to take on faith. See
`Examples.WheelBrakeCompleted` for a completed version, and
`Examples.WheelBrakeSec` for an STPA-Sec (security) extension.

Control structure (STPA Handbook Fig 2.12, generic aircraft braking loop):

```
  flightCrew ──bscuPower──▶ bscu ──brakeCmd──▶ hydraulics ──brakePressure──▶ aircraft
      ▲                      ▲                                                  │
      │                      └──────────speedFeedback──── wheelSensors ◀────wheelSpeed
      └──────────bscuFault───┘
  flightCrew ──manualBrake──▶ hydraulics
```

`bscuPower` (flightCrew → bscu) is a controller→controller authority edge:
the crew has command authority to power the BSCU on/off. `bscuFault`
(bscu → flightCrew) is upward controller→controller status feedback. Both
are exercised deliberately to cover the authority-DAG and status-reporting
cases of `ControlStructure.pathsWellFormed`.
-/

namespace Examples.WheelBrake

open Sysml Sysml.Kernel Sysml.Stpa

sysml wbsModel {
  package WheelBrakeSystem {
    part def FlightCrew;
    part def Bscu;
    part def HydraulicSystem;
    part def Aircraft;
    part def WheelSensorSuite;
    item def PowerCommand;
    item def BrakeCommand;
    item def HydraulicPressure;
    item def ManualBrakeForce;
    item def WheelRotation;
    item def SpeedReading;
    item def FaultIndication;

    part flightCrew : FlightCrew {
      out port powerOut;
      out port manualOut;
      in port faultIn;
    }
    part bscu : Bscu {
      in port powerIn;
      out port brakeOut;
      in port speedIn;
      out port faultOut;
    }
    part hydraulics : HydraulicSystem {
      in port brakeIn;
      in port manualIn;
      out port pressureOut;
    }
    part aircraft : Aircraft {
      in port pressureIn;
      out port wheelsOut;
    }
    part wheelSensors : WheelSensorSuite {
      in port wheelsIn;
      out port speedOut;
    }

    flow bscuPower of PowerCommand from flightCrew.powerOut to bscu.powerIn;
    flow brakeCmd of BrakeCommand from bscu.brakeOut to hydraulics.brakeIn;
    flow manualBrake of ManualBrakeForce from flightCrew.manualOut to hydraulics.manualIn;
    flow brakePressure of HydraulicPressure from hydraulics.pressureOut to aircraft.pressureIn;
    flow wheelSpeed of WheelRotation from aircraft.wheelsOut to wheelSensors.wheelsIn;
    flow speedFeedback of SpeedReading from wheelSensors.speedOut to bscu.speedIn;
    flow bscuFault of FaultIndication from bscu.faultOut to flightCrew.faultIn;
  }
}

/-- Recover ids assigned by the DSL by name. -/
private def wid (n : Name) : ElementId := wbsModel.idOf n

/-- The functional control structure over `wbsModel` (STPA Handbook Fig 2.12). -/
def cs : ControlStructure where
  roles := [
    (wid "flightCrew", .controller),
    (wid "bscu", .controller),
    (wid "hydraulics", .actuator),
    (wid "aircraft", .controlledProcess),
    (wid "wheelSensors", .sensor)
  ]
  controlPaths := [wid "bscuPower", wid "brakeCmd", wid "manualBrake", wid "brakePressure"]
  feedbackPaths := [wid "wheelSpeed", wid "speedFeedback", wid "bscuFault"]

/-- STPA step 1: losses (STPA Handbook p.17 examples). -/
def losses : List Loss := [
  ⟨1, "Loss of life or injury to people"⟩,
  ⟨2, "Loss of or damage to vehicle"⟩,
  ⟨5, "Loss of customer satisfaction"⟩
]

/-- STPA step 1: hazards. These are the sub-hazards of H-4 "Aircraft comes
too close to other objects on the ground [L-1, L-2, L-5]" — ids `4x` for
H-4.x, all tracing to losses L-1, L-2, L-5. The handbook lists H-4.1
through H-4.6; we transcribe the ones exercised by the BSCU autobrake
tables (H-4.5, about rejected takeoff, is folded into the Table 2.3/2.5
inconsistency noted on UCA 2 below and is not separately transcribed). -/
def hazards : List Hazard := [
  { id := 41, desc := "H-4.1: Deceleration is insufficient upon landing, rejected takeoff, or during taxiing", losses := [1, 2, 5] },
  { id := 42, desc := "H-4.2: Asymmetric deceleration maneuvers aircraft toward other objects", losses := [1, 2, 5] },
  { id := 43, desc := "H-4.3: Deceleration occurs after V1 point during takeoff", losses := [1, 2, 5] },
  { id := 44, desc := "H-4.4: Excessive acceleration provided while taxiing", losses := [1, 2, 5] },
  { id := 46, desc := "H-4.6: Acceleration is insufficient during takeoff", losses := [1, 2, 5] }
]

/-- STPA step 1: system-level constraints (Table 2.1 — deceleration only).
The handbook derives no constraint for the acceleration sub-hazards
H-4.4/H-4.6 in this excerpt — they are left unconstrained ON PURPOSE, as
published. -/
def constraints : List SystemConstraint := [
  { id := 61, desc := "SC-6.1: Deceleration must occur within TBD seconds of landing or rejected takeoff at a rate of at least TBD m/s2", hazards := [41] },
  { id := 62, desc := "SC-6.2: Asymmetric deceleration must not lead to loss of directional control or cause aircraft to depart taxiway, runway, or apron", hazards := [42] },
  { id := 63, desc := "SC-6.3: Deceleration must not be provided after V1 point during takeoff", hazards := [43] }
]

/-- STPA step 3: unsafe control actions (Table 2.3, BSCU Autobrake "Brake"
control action = `brakeCmd`; plus Crew-UCA-1 on `bscuPower`). -/
def ucas : List Uca := [
  { id := 1, action := wid "brakeCmd", kind := .notProviding,
    context := "UCA-1: during landing roll when the BSCU is armed", hazards := [41] },
  -- NOTE: Table 2.3 traces this UCA to [H-4.3, H-4.6], but Table 2.5 and the
  -- surrounding body text say [H-4.3, H-4.5] — a handbook-internal
  -- inconsistency. We follow Table 2.3.
  { id := 2, action := wid "brakeCmd", kind := .providing,
    context := "UCA-2: during a normal takeoff", hazards := [43, 46] },
  { id := 3, action := wid "brakeCmd", kind := .wrongTiming,
    context := "UCA-3: too late (>TBD seconds) after touchdown", hazards := [41] },
  { id := 4, action := wid "brakeCmd", kind := .wrongDuration,
    context := "UCA-4: stops too early (before TBD taxi speed attained) when aircraft lands", hazards := [41] },
  { id := 5, action := wid "brakeCmd", kind := .providing,
    context := "UCA-5: with an insufficient level of braking during landing roll", hazards := [41] },
  { id := 6, action := wid "brakeCmd", kind := .providing,
    context := "UCA-6: with directional or asymmetrical braking during landing roll", hazards := [41, 42] },
  { id := 7, action := wid "bscuPower", kind := .notProviding,
    context := "Crew-UCA-1: crew does not provide BSCU Power Off when abnormal WBS behavior occurs", hazards := [41, 44] }
]

/-- No explicit not-applicable dispositions are transcribed: the handbook
does not dispose the remaining coverage cells in this excerpt — that
absence is itself part of the published incompleteness we are pinning. -/
def notApplicable : List (ElementId × UcaKind × String) := []

/-- STPA step 3: controller requirements (Table 2.5, C-1..C-6, one per
UCA 1-6). There is deliberately no requirement for Crew-UCA-1 (UCA 7) —
it is ORPHANED, as published. -/
def requirements : List Requirement := [
  { id := 1, desc := "C-1: BSCU Autobrake must provide the Brake control action during landing roll when the BSCU is armed", ucas := [1] },
  { id := 2, desc := "C-2: BSCU Autobrake must not provide Brake control action during a normal takeoff", ucas := [2] },
  { id := 3, desc := "C-3: BSCU Autobrake must provide the Brake control action within TBD seconds after touchdown", ucas := [3] },
  { id := 4, desc := "C-4: BSCU Autobrake must not stop providing the Brake control action before TBD taxi speed is attained during landing roll", ucas := [4] },
  { id := 5, desc := "C-5: BSCU Autobrake must not provide less than TBD level of braking during landing roll", ucas := [5] },
  { id := 6, desc := "C-6: BSCU Autobrake must not provide directional or asymmetrical braking during landing roll", ucas := [6] }
]

/-- STPA step 4: loss scenarios (handbook examples). UCAs 4, 5, 6 have none
transcribed here — ON PURPOSE, as published. -/
def scenarios : List Scenario := [
  ⟨1, 1, "Scenario 1 for UCA-1: the BSCU Autobrake physical controller fails during landing roll when BSCU is armed, causing the Brake control action to not be provided; insufficient deceleration upon landing"⟩,
  ⟨2, 3, "Scenario 1 for UCA-3: the aircraft lands, but processing delays within the BSCU result in the Brake control action being provided too late"⟩,
  ⟨3, 2, "Scenario 1 for UCA-2: flawed process model — received feedback momentarily indicates zero speed during anti-skid operation, so the BSCU believes the aircraft has stopped"⟩,
  ⟨4, 2, "Scenario 2 for UCA-2: touchdown indication is not received upon touchdown (insufficient reported wheel speed or weight-on-wheels), so the BSCU believes the aircraft is still in the air"⟩,
  ⟨5, 7, "Scenario 1 for Crew-UCA-1: a BSCU fault indication is provided but operating procedures did not specify that the crew must power off the BSCU upon receiving it"⟩
]

/-- The assembled STPA analysis, transcribed as published: NOT well-formed
(see `wbs_docNotWellFormed`), and pinned to produce exactly the 17 findings
in `expectedGaps`. -/
def analysis : Analysis where
  model := wbsModel
  cs := cs
  losses := losses
  hazards := hazards
  constraints := constraints
  ucas := ucas
  notApplicable := notApplicable
  requirements := requirements
  scenarios := scenarios

/-! ## Certificates -/

/-- The wheel-brake model is well-formed SysML. -/
theorem wbsModel_wellFormed : wbsModel.wellFormed = true := by decide

/-- The control structure is well-formed: closed loops, and an acyclic
authority hierarchy over the crew→bscu authority edge. -/
theorem wbsCs_wellFormed : cs.wellFormed wbsModel = true := by decide

/-- The published tables are self-declared partial: the analysis document
is NOT well-typed. This is the point of this transcription — the gap is a
pinned, reproducible fact about the source material, not an oversight
here. -/
theorem wbs_docNotWellFormed : analysis.docWellFormed = false := by decide

/-- The exact 17 findings the checker produces against the published,
partial tables:
- 2 `hazard-unconstrained` (H44, H46 — Table 2.1 derives no constraint for
  the acceleration sub-hazards),
- 11 `uca-coverage-gap` (bscuPower × providing/wrongTiming/wrongDuration;
  manualBrake × all four guide phrases; brakePressure × all four guide
  phrases — the handbook tables analyze only the `brakeCmd` control action
  in this excerpt),
- 1 `uca-orphaned` (UCA7, Crew-UCA-1 — no C-7 requirement is derived here),
- 3 `uca-no-scenario` (UCA4, UCA5, UCA6 — Table 2.5's scenario column is
  populated only for UCA-1, UCA-2, and UCA-3 in this excerpt).

This is *the* measurement this file exists to make: it quantifies exactly
how incomplete the handbook's own self-declared-partial example is. -/
def expectedGaps : List (String × String) := [
  ("hazard-unconstrained", "H44"),
  ("hazard-unconstrained", "H46"),
  ("uca-coverage-gap", "bscuPower × providing"),
  ("uca-coverage-gap", "bscuPower × too early / too late / out of order"),
  ("uca-coverage-gap", "bscuPower × stopped too soon / applied too long"),
  ("uca-coverage-gap", "manualBrake × not providing"),
  ("uca-coverage-gap", "manualBrake × providing"),
  ("uca-coverage-gap", "manualBrake × too early / too late / out of order"),
  ("uca-coverage-gap", "manualBrake × stopped too soon / applied too long"),
  ("uca-coverage-gap", "brakePressure × not providing"),
  ("uca-coverage-gap", "brakePressure × providing"),
  ("uca-coverage-gap", "brakePressure × too early / too late / out of order"),
  ("uca-coverage-gap", "brakePressure × stopped too soon / applied too long"),
  ("uca-orphaned", "UCA7"),
  ("uca-no-scenario", "UCA4"),
  ("uca-no-scenario", "UCA5"),
  ("uca-no-scenario", "UCA6")
]

theorem wbs_gaps :
    analysis.findings.map (fun f => (f.check, f.subject)) = expectedGaps := by decide

-- Round-trip: print the elaborated model back as SysML textual notation.
-- #sysml wbsModel

end Examples.WheelBrake
