/-!
# Core notions shared by all layers

Spec: OMG SysML v2, formal/2026-03-02 (Part 1). This module holds the small
vocabulary shared between the deep metamodel layer (`Sysml.Kernel`) and the
STPA-facing view (`Sysml.View`, `Sysml.Stpa`).
-/

namespace Sysml

/-- Simple names; qualified names (§7.5) are out of scope for now. -/
abbrev Name := String

/-- Feature direction (§7.12 ports, §7.16 flows). `in` is a Lean keyword. -/
inductive Direction where
  | «in»
  | out
  | inout
deriving DecidableEq, Repr

/-- The direction seen from the other end of a connection. -/
def Direction.opposite : Direction → Direction
  | .«in» => .out
  | .out => .«in»
  | .inout => .inout

/-- `d.conforms d'` iff an item can flow from a feature with direction `d`
to one with direction `d'` (§7.13, §7.16). -/
def Direction.conforms : Direction → Direction → Bool
  | .out, .«in» => true
  | .inout, _ => true
  | _, .inout => true
  | _, _ => false

end Sysml
