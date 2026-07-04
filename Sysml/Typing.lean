import Sysml.Stpa

/-!
# A type system for STPA documents

The judgments of docs/stpa-typesystem.pdf, stated as Props over an
`Analysis`. Each per-artifact judgment says what it means for that artifact
to be well-typed in the document; `WellTyped` bundles them, mirroring the
typing rules one-for-one. The reflection theorem `wellTyped_iff` proves that
the executable checker `Analysis.docWellFormed` decides exactly this
predicate — so the paper's type system and the running checker cannot drift
apart, and `decide` certifies concrete documents against the Prop-level
rules.

The central judgment is `UcaRefined`: an *orphaned* UCA — one refined by no
controller requirement — is precisely a non-exhaustiveness error.
-/

namespace Sysml.Stpa

open Sysml.Kernel

/-! ## Per-artifact judgments -/

/-- `⊢ h ok`: a hazard traces to at least one declared loss. -/
def HazardOk (a : Analysis) (h : Hazard) : Prop :=
  h.losses ≠ [] ∧ ∀ l ∈ h.losses, ∃ loss ∈ a.losses, loss.id = l

/-- `⊢ c ok`: a system constraint traces to at least one declared hazard. -/
def ConstraintOk (a : Analysis) (c : SystemConstraint) : Prop :=
  c.hazards ≠ [] ∧ ∀ h ∈ c.hazards, ∃ hz ∈ a.hazards, hz.id = h

/-- Hazard totality: some system constraint addresses `h`. -/
def HazardConstrained (a : Analysis) (h : Hazard) : Prop :=
  ∃ c ∈ a.constraints, h.id ∈ c.hazards

/-- `⊢ u ok`: a UCA names a declared control path and traces to at least
one declared hazard. -/
def UcaOk (a : Analysis) (u : Uca) : Prop :=
  u.action ∈ a.cs.controlPaths
    ∧ u.hazards ≠ [] ∧ ∀ h ∈ u.hazards, ∃ hz ∈ a.hazards, hz.id = h

/-- Coverage: control path `c` is considered under guide phrase `k` —
either a UCA exists or an explicit N/A verdict was recorded. -/
def Considered (a : Analysis) (c : ElementId) (k : UcaKind) : Prop :=
  (∃ u ∈ a.ucas, u.action = c ∧ u.kind = k)
    ∨ ∃ na ∈ a.notApplicable, na.1 = c ∧ na.2.1 = k

/-- `⊢ r ok`: a requirement refines at least one declared UCA, and its
optional model binding points at a SysML requirement usage. -/
def RequirementOk (a : Analysis) (r : Requirement) : Prop :=
  r.ucas ≠ [] ∧ (∀ u ∈ r.ucas, ∃ uca ∈ a.ucas, uca.id = u)
    ∧ ∀ e ∈ r.element, a.model.kindOf? e = some .requirementUsage

/-- UCA totality — the central judgment: some requirement refines `u`.
Its negation is an *orphaned UCA*, a non-exhaustiveness error. -/
def UcaRefined (a : Analysis) (u : Uca) : Prop :=
  ∃ r ∈ a.requirements, u.id ∈ r.ucas

/-- `⊢ s ok`: a loss scenario explains a declared UCA. -/
def ScenarioOk (a : Analysis) (s : Scenario) : Prop :=
  ∃ u ∈ a.ucas, u.id = s.uca

/-- Scenario totality (STPA step 4): some loss scenario explains `u`. -/
def UcaExplained (a : Analysis) (u : Uca) : Prop :=
  ∃ s ∈ a.scenarios, s.uca = u.id

/-! ## The document judgment -/

/-- `⊢ a ok`: every artifact is well-kinded and referentially intact, every
control path is covered under all four guide phrases, and both totality
conditions hold (every hazard constrained, every UCA refined). -/
structure WellTyped (a : Analysis) : Prop where
  hazards_ok : ∀ h ∈ a.hazards, HazardOk a h
  constraints_ok : ∀ c ∈ a.constraints, ConstraintOk a c
  hazards_constrained : ∀ h ∈ a.hazards, HazardConstrained a h
  ucas_ok : ∀ u ∈ a.ucas, UcaOk a u
  ucas_covered : ∀ c ∈ a.cs.controlPaths, ∀ k ∈ UcaKind.all, Considered a c k
  requirements_ok : ∀ r ∈ a.requirements, RequirementOk a r
  ucas_refined : ∀ u ∈ a.ucas, UcaRefined a u
  scenarios_ok : ∀ s ∈ a.scenarios, ScenarioOk a s
  ucas_explained : ∀ u ∈ a.ucas, UcaExplained a u

/-! ## Reflection: the checker decides the judgment -/

namespace Analysis

theorem hazardsTraceable_iff (a : Analysis) :
    a.hazardsTraceable = true ↔ ∀ h ∈ a.hazards, HazardOk a h := by
  simp [hazardsTraceable, HazardOk, List.all_eq_true, List.any_eq_true]

theorem constraintsTraceable_iff (a : Analysis) :
    a.constraintsTraceable = true ↔ ∀ c ∈ a.constraints, ConstraintOk a c := by
  simp [constraintsTraceable, ConstraintOk, List.all_eq_true, List.any_eq_true]

theorem hazardsConstrained_iff (a : Analysis) :
    a.hazardsConstrained = true ↔ ∀ h ∈ a.hazards, HazardConstrained a h := by
  simp [hazardsConstrained, HazardConstrained, List.all_eq_true,
    List.any_eq_true]

theorem ucasTraceable_iff (a : Analysis) :
    a.ucasTraceable = true ↔ ∀ u ∈ a.ucas, UcaOk a u := by
  simp [ucasTraceable, UcaOk, List.all_eq_true, List.any_eq_true,
    and_assoc]

theorem ucasCover_iff (a : Analysis) :
    a.ucasCover = true ↔
      ∀ c ∈ a.cs.controlPaths, ∀ k ∈ UcaKind.all, Considered a c k := by
  simp [ucasCover, Considered, List.all_eq_true, List.any_eq_true]

theorem requirementsTraceable_iff (a : Analysis) :
    a.requirementsTraceable = true ↔ ∀ r ∈ a.requirements, RequirementOk a r := by
  simp only [requirementsTraceable, RequirementOk, List.all_eq_true]
  refine forall_congr' fun r => forall_congr' fun _ => ?_
  cases hr : r.element <;>
    simp [List.all_eq_true, List.any_eq_true, and_assoc]

theorem ucasRefined_iff (a : Analysis) :
    a.ucasRefined = true ↔ ∀ u ∈ a.ucas, UcaRefined a u := by
  simp [ucasRefined, UcaRefined, List.all_eq_true, List.any_eq_true]

theorem scenariosTraceable_iff (a : Analysis) :
    a.scenariosTraceable = true ↔ ∀ s ∈ a.scenarios, ScenarioOk a s := by
  simp [scenariosTraceable, ScenarioOk, List.all_eq_true, List.any_eq_true]

theorem scenariosCover_iff (a : Analysis) :
    a.scenariosCover = true ↔ ∀ u ∈ a.ucas, UcaExplained a u := by
  simp [scenariosCover, UcaExplained, List.all_eq_true, List.any_eq_true]

/-- Soundness and completeness of the checker: `docWellFormed` decides the
`WellTyped` judgment. -/
theorem wellTyped_iff (a : Analysis) :
    a.docWellFormed = true ↔ WellTyped a := by
  simp only [docWellFormed, Bool.and_eq_true, hazardsTraceable_iff,
    constraintsTraceable_iff, hazardsConstrained_iff, ucasTraceable_iff,
    ucasCover_iff, requirementsTraceable_iff, ucasRefined_iff,
    scenariosTraceable_iff, scenariosCover_iff]
  constructor
  · rintro ⟨⟨⟨⟨⟨⟨⟨⟨h₁, h₂⟩, h₃⟩, h₄⟩, h₅⟩, h₆⟩, h₇⟩, h₈⟩, h₉⟩
    exact ⟨h₁, h₂, h₃, h₄, h₅, h₆, h₇, h₈, h₉⟩
  · rintro ⟨h₁, h₂, h₃, h₄, h₅, h₆, h₇, h₈, h₉⟩
    exact ⟨⟨⟨⟨⟨⟨⟨⟨h₁, h₂⟩, h₃⟩, h₄⟩, h₅⟩, h₆⟩, h₇⟩, h₈⟩, h₉⟩

instance (a : Analysis) : Decidable (WellTyped a) :=
  decidable_of_iff (a.docWellFormed = true) (wellTyped_iff a)

end Analysis

end Sysml.Stpa
