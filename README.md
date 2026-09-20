# Prospero

A Claude Code plugin that decides how much model each piece of work deserves.
Named after the magician in *The Tempest*, who hands every task to the spirit
fit for it; the workers it dispatches are called Ariel.

- Every subagent dispatch is judged by Haiku first. A dispatch that names no
  model gets the judged one. A `general-purpose` dispatch is also retargeted to
  `prospero:ariel-low|medium|high`, because reasoning effort cannot be passed
  per dispatch and has to come from the agent definition.
- Every prompt you type is judged in the background, for the log only. It is
  never delayed or changed. Start a prompt with `cx:` to see the verdict
  instead of running it.
- It fails open: if the judge fails or times out, the dispatch runs unchanged.

```
cx: add a GET /api/orders/:id endpoint like the users one
→ sonnet · medium — follows an existing pattern across a few files
```

## What it costs

Each typed prompt longer than three words and each subagent dispatch starts one
`claude -p --model haiku` call. A dispatch that gets retargeted waits for it,
about 10 seconds. Nested subagents are judged at every layer.

## Install

Needs `bash`, `jq`, `perl` and the `claude` CLI on `PATH`.

```
/plugin marketplace add herynto/prospero-harness
/plugin install prospero@prospero
```

Settings live in `~/.prospero/`, outside the plugin, so updates keep them. The
first prompt after install creates `~/.prospero/bin/prospero-config`, a stable
path to the settings CLI. Add it to your shell once:

```bash
export PATH="$HOME/.prospero/bin:$PATH"
```

## Settings

`prospero-config` edits `~/.prospero/config.json`. It runs in your terminal and
costs no tokens. From inside Claude Code use `! prospero-config …`.

| Command | Effect |
|---------|--------|
| `prospero-config show` | every pair, the mode and both switches |
| `prospero-config edit` | arrow-key menu for everything below |
| `prospero-config set opus/medium sonnet/high` | when the verdict is `opus/medium`, run `sonnet/high` instead |
| `prospero-config mode [name]` | how the judge weighs doubt: `balanced`, `cheap`, `quality` |
| `prospero-config switch override_chosen true` | also replace a model the session picked itself |
| `prospero-config switch swap_agents false` | stop retargeting to `ariel-*`; only the model is filled in |
| `prospero-config reset` | back to defaults |

No access to `fable`? Map it away once:

```bash
for e in low medium high; do prospero-config set fable/$e opus/$e; done
```

Missing, broken or misspelt settings fall back to the verdict; a bad pair is
noted as `config_error` in the log.

## Files

| File | Job |
|------|-----|
| `hooks/hooks.json` | registers the two hooks below |
| `hook.sh` | `UserPromptSubmit`: judges every prompt into the log; `cx:` prompts show the verdict and block. Follow-ups ("ok continue") reuse the session's last verdict: three words or fewer skip the model call, longer ones are flagged by the judge through `"followup": true`. |
| `dispatch-hook.sh` | `PreToolUse` on `Agent\|Task`: fills in the model, retargets `general-purpose` to `ariel-<effort>`. Other agent types are untouched. |
| `classify` | text on stdin → `{"model","effort","reason","followup","mode"}` on stdout; exits non-zero instead of guessing |
| `prompt.md` | the judging rules |
| `modes/<name>.md` | extra rules appended to `prompt.md` when that mode is active, so the judge itself takes a different stance. Any new file here becomes a mode; unknown names fall back to `balanced`. `PROSPERO_MODE` sets it for one call. |
| `agents/ariel-{low,medium,high}.md` | general-purpose workers that differ only in `effort:` |
| `bin/prospero-config` | the settings CLI |

Data, all under `~/.prospero/` (`PROSPERO_HOME` moves it):

| File | Holds |
|------|-------|
| `config.json` | your settings |
| `log.jsonl` | one line per judgment: the verdict (`model`, `effort`, `reason`, `mode`) and, for dispatches (`"source": "dispatch"`), the outcome (`final_model`, `final_effort`, `chosen`, `applied`, `agent`). Holds prompt text; never leaves your machine. |
| `state/<session_id>.json` | the session's last verdict, for follow-ups |

`classify` sets `PROSPERO_CLASSIFYING=1` before it calls `claude -p`. That
nested call fires the hooks again; they exit at once when they see the
variable. Remove the guard and it loops forever. Set the same variable on your
own scripted `claude -p` calls to keep Prospero off them.

## Without the plugin system

Point `hooks.UserPromptSubmit` and `hooks.PreToolUse` (matcher `Agent|Task`,
`"timeout": 60`) in `~/.claude/settings.json` at `hook.sh` and
`dispatch-hook.sh`, and link the agents:
`ln -s "$PWD"/agents/ariel-*.md ~/.claude/agents/`. The agents are then named
`ariel-*` without the `prospero:` prefix, which the hook handles.

## Tests

```bash
tests/hook_test.sh           # exact, judge stubbed
tests/classify_test.sh       # exact, claude stubbed
tests/dispatch_hook_test.sh  # exact, judge stubbed
tests/run.sh                 # real model, 15 labelled prompts, ~2 min
```

`tests/run.sh` passes when the model matches on at least 12 of 15 and no
verdict is more than one tier off. Fix misses in `prompt.md`, never by
relabelling a case. `PROSPERO_MODE=quality tests/run.sh` scores another mode
against the same labels, which were written for `balanced`; read it as "how far
does this mode move", not pass/fail.

## License

MIT, see `LICENSE`.
