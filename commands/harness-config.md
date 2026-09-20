---
description: View and change the harness model/effort preferences interactively
allowed-tools: Bash(/Users/heryanto/harness/config:*), AskUserQuestion
---

Help the user edit `~/harness/config.json`, the preferences the harness dispatch hook
applies to every classifier verdict. Only ever change it through
`/Users/heryanto/harness/config`; never edit the file by hand.

1. Run `/Users/heryanto/harness/config show` and show the table as it is. Rows marked
   `*` differ from the default. Left is the classifier's verdict, right is what runs.
2. If `$ARGUMENTS` already says what to change (for example "opus/medium jadi fable/low"),
   skip to step 4 with that.
3. Otherwise ask with the AskUserQuestion tool what to change: one verdict pair, one
   switch (`override_chosen`, `swap_agents`), reset everything, or nothing. For a pair,
   ask which verdict (model, then effort) and then which model and effort should run
   instead. Offer only haiku, sonnet, opus, fable and low, medium, high.
4. Apply it with `config set <from> <to>`, `config switch <name> <true|false>` or
   `config reset`. If the command prints an error, show it and ask again.
5. Show `config show` once more, then ask whether to change anything else. Loop until
   the user is done.

Facts to tell the user when relevant, in one line each:
- Changes apply to the next subagent dispatch; no restart.
- With `override_chosen = false`, a dispatch that already names a model keeps it; only
  the effort side of the mapping applies.
- Effort only applies to `general-purpose` dispatches, through the `harness-<effort>` agents.
