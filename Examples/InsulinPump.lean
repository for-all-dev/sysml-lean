import Sysml.Dsl
import Sysml.Stpa
import Sysml.Viz

/-!
# Worked example: insulin infusion pump

A miniature closed-loop insulin pump, written in SysML v2 textual notation
via the `sysml` command (`Sysml.Dsl`) and analyzed with STPA. The control
structure is the textbook loop:

```
  pumpController ──deliverCmd──▶ pumpMotor ──insulinFlow──▶ patient
        ▲                                                      │
        └────readingFlow──── cgmSensor ◀────glucoseFlow────────┘
```

The theorems at the bottom certify, by computation, that the model is
well-formed SysML, that the control structure is a closed loop, and that
the STPA artifacts are traceable and cover all four UCA kinds for every
control path.
-/

namespace Examples.InsulinPump

open Sysml Sysml.Kernel Sysml.Stpa

sysml pumpModel {
  package InsulinPumpSystem {
    part def Controller;
    part def Motor;
    part def Human;
    part def GlucoseMonitor;
    item def Insulin;
    item def GlucoseReading;
    item def InsulinCommand;
    item def Glucose;

    part pumpController : Controller {
      out port cmdOut;
      in port readingIn;
    }
    part pumpMotor : Motor {
      in port cmdIn;
      out port insulinOut;
    }
    part patient : Human {
      in port insulinIn;
      out port glucoseOut;
    }
    part cgmSensor : GlucoseMonitor {
      in port glucoseIn;
      out port readingOut;
    }

    flow deliverCmd of InsulinCommand from pumpController.cmdOut to pumpMotor.cmdIn;
    flow insulinFlow of Insulin from pumpMotor.insulinOut to patient.insulinIn;
    flow glucoseFlow of Glucose from patient.glucoseOut to cgmSensor.glucoseIn;
    flow readingFlow of GlucoseReading from cgmSensor.readingOut to pumpController.readingIn;
  }
}

/-- Recover ids assigned by the DSL by name. -/
private def pid (n : Name) : ElementId := pumpModel.idOf n

/-- The functional control structure over `pumpModel`. -/
def pumpCs : ControlStructure where
  roles := [
    (pid "pumpController", .controller),
    (pid "pumpMotor", .actuator),
    (pid "patient", .controlledProcess),
    (pid "cgmSensor", .sensor)
  ]
  controlPaths := [pid "deliverCmd", pid "insulinFlow"]
  feedbackPaths := [pid "glucoseFlow", pid "readingFlow"]

/-- STPA step 1: losses. -/
def losses : List Loss := [
  ⟨1, "Patient death or serious injury"⟩,
  ⟨2, "Patient illness requiring medical intervention"⟩
]

/-- STPA step 1: hazards, including one security-framed (STPA-Sec) hazard. -/
def hazards : List Hazard := [
  { id := 1, desc := "Pump delivers insulin when blood glucose is low",
    losses := [1] },
  { id := 2, desc := "Pump fails to deliver insulin when blood glucose is sustained high",
    losses := [1, 2] },
  { id := 3, desc := "Command channel accepts insulin commands not originating from the controller",
    kind := .security, losses := [1, 2] }
]

/-- STPA step 3: unsafe control actions for the `deliverCmd` control path. -/
def ucas : List Uca := [
  { id := 1, action := pid "deliverCmd", kind := .notProviding,
    context := "blood glucose sustained above threshold", hazards := [2] },
  { id := 2, action := pid "deliverCmd", kind := .providing,
    context := "blood glucose at or below threshold", hazards := [1] },
  { id := 3, action := pid "deliverCmd", kind := .wrongTiming,
    context := "bolus commanded too long after mealtime glucose rise", hazards := [2] },
  { id := 4, action := pid "deliverCmd", kind := .wrongDuration,
    context := "bolus delivery applied longer than commanded dose", hazards := [1] }
]

/-- The physical insulin flow is a control path (actuator → process) but its
hazards are analyzed via the command path, so its UCA slots are justified
not-applicable. -/
def notApplicable : List (ElementId × UcaKind × String) :=
  UcaKind.all.map fun k =>
    (pid "insulinFlow", k, "physical delivery path; unsafe behavior analyzed on deliverCmd")

/-- The assembled STPA analysis. -/
def analysis : Analysis where
  model := pumpModel
  cs := pumpCs
  losses := losses
  hazards := hazards
  ucas := ucas
  notApplicable := notApplicable

/-! ## Certificates -/

/-- The pump model is well-formed SysML (§7.5, §7.6, §7.13 constraints). -/
theorem pumpModel_wellFormed : pumpModel.wellFormed = true := by decide

/-- The control structure is well-formed and every control loop is closed:
the controller receives feedback from every process it controls. -/
theorem pumpCs_wellFormed : pumpCs.wellFormed pumpModel = true := by decide

/-- The full STPA analysis is well-formed: traceable hazards and UCAs, and
all four UCA kinds covered for every control path. -/
theorem analysis_wellFormed : analysis.wellFormed = true := by decide

-- Round-trip: print the elaborated model back as SysML textual notation.
-- #sysml pumpModel

end Examples.InsulinPump
