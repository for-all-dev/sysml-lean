import Sysml.Kernel.WellFormed

/-!
# View layer: STPA-friendly projections

Curated, typed views over the abstract-syntax graph of `Sysml.Kernel`. STPA
works with a *functional control structure*: blocks (parts) exchanging
control actions and feedback over connections. This module recovers that
part-level graph from the port-level model.
-/

namespace Sysml.View

open Sysml.Kernel

/-- The part usage that (transitively) owns a feature: walk up the ownership
chain to the first `partUsage`. Fuel-bounded, so total on any model. -/
def ownerPart? (m : Model) (x : ElementId) : Option ElementId :=
  go m.elements.length x
where
  go : Nat → ElementId → Option ElementId
    | 0, _ => none
    | fuel + 1, y => do
      let e ← m.find? y
      let o ← e.owner
      let oe ← m.find? o
      if oe.kind = .partUsage then some o else go fuel o

/-- A part-level edge: connection or flow `conn` links the part owning its
source port to the part owning its target port. -/
structure Link where
  conn : ElementId
  sourcePart : ElementId
  targetPart : ElementId
deriving DecidableEq, Repr

/-- All part-level links induced by the model's connections and flows. -/
def links (m : Model) : List Link :=
  m.elements.filterMap fun e =>
    if e.kind = .connectionUsage ∨ e.kind = .flowUsage then do
      let s ← m.endOf? e.id 0
      let t ← m.endOf? e.id 1
      let sp ← ownerPart? m s
      let tp ← ownerPart? m t
      some ⟨e.id, sp, tp⟩
    else none

/-- Is `b` reachable from `a` along the given edges? Fuel-bounded DFS over
at most `edges.length` steps, hence total and decidable. -/
def reachable (edges : List (ElementId × ElementId)) (a b : ElementId) : Bool :=
  go edges.length [a] []
where
  go : Nat → List ElementId → List ElementId → Bool
    | _, [], _ => false
    | 0, frontier, _ => frontier.contains b
    | fuel + 1, frontier, visited =>
      if frontier.contains b then true
      else
        let visited := frontier ++ visited
        let next := (edges.filterMap fun (s, t) =>
          if frontier.contains s && !visited.contains t then some t else none).eraseDups
        go fuel next visited

end Sysml.View
