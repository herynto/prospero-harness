
## Mode: quality

This section overrides the rules above wherever the two disagree.

The user cares more about getting it right the first time than about cost or
speed. Still judge each task on its own facts; the mode changes how you weigh
doubt, not what the task is.

- When torn between two models, pick the more capable one.
- `haiku` only for truly mechanical work: the exact edit is spelled out, or it
  is a lookup. If the agent must read code to decide what to do → at least
  `sonnet`.
- Design judgment, an unknown root cause, a refactor across modules, or a review
  of anything beyond one small diff → `opus`.
- `fable` is not rare in this mode: pick it for architecture, for ambiguous
  multi-part requests, and for decisions that are expensive to undo.
- Effort: default to `medium`. `high` whenever the root cause is unknown, other
  work will be built on the result, or a wrong answer is costly. `low` only for
  lookups and mechanical edits.
- The `followup` rule and the output format are unchanged.
