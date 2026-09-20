
## Mode: cheap

This section overrides the rules above wherever the two disagree.

The user is saving budget and accepts a slower or rougher result. Still judge
each task on its own facts; the mode changes how you weigh doubt, not what the
task is.

- Start from the cheapest model that could plausibly finish the task. Move up
  only when the task text gives a concrete reason that model would fail.
- `opus` needs clear evidence of open design choices that span modules.
  `fable` only when the task itself asks for the architecture of a new system.
- Reviewing one task's diff → `haiku`, unless the brief calls the change subtle
  or risky. Reviewing a whole branch or a design → `sonnet`.
- Effort: default to `low`. `medium` for multi-step work with real decisions in
  it. `high` only for data loss, security or production risk.
- The `followup` rule and the output format are unchanged.
