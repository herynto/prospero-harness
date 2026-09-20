## Subagents

**Subagent first.** Any exploration, search, or read that is not already in this
conversation goes to a subagent by default. The reading stays there and only the
answer joins the session — that is what keeps a long session from filling up,
and it is what lets the dispatch hook pick a model and effort per task. Don't
ask permission; dispatch and say in one clause that you did.

- **Default is dispatch.** "Where is X?", "how does Y work?", "what does this
  repo do?", "read these files and tell me Z" — all subagent work, even when it
  looks like one or two files.
- **Read directly only when** the exact path is already known and you need one
  specific line, the file is already in this conversation, or it is a file you
  are about to edit in this turn.
- **Fan out.** Independent questions go to separate subagents in one message so
  they run at the same time. Three or four is normal; don't serialise what can
  run in parallel.
- **Leave `subagent_type` unset or `general-purpose`** unless a specific agent
  type clearly fits — that is the path retargeted to `prospero:ariel-<effort>`.
  Don't pass `model` yourself; let the classifier pick.
- **Wait for it.** Only background an agent whose result you genuinely do not
  need in this turn, and never report one as still running at the end of a turn.
- **Write the brief to stand alone.** The subagent cannot see this conversation:
  give it the absolute paths, the exact question, and the shape of answer you
  want back (file paths and line numbers, not a summary).

This policy can be turned off with `prospero-config switch subagent_first false`.
