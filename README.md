# harness

A small agent harness for Claude Code, built one layer at a time.

## Stage 1 — classification layer (current)

Type a prompt starting with `cx:` in Claude Code. A `UserPromptSubmit` hook
sends the text to Haiku, which picks a model and a reasoning effort for the
task. The verdict is shown and logged, and the prompt is blocked — the task
does not run. Prompts without `cx:` run as usual; they are classified in the background
(no delay) and the verdict only goes to `log.jsonl` with `"source": "auto"`.

```
cx: add a GET /api/orders/:id endpoint like the users one
→ sonnet · medium — follows an existing pattern across a few files
```

| File | Job |
|------|-----|
| `classify` | prompt on stdin → `{"model","effort","reason"}` on stdout; exits non-zero instead of guessing |
| `hook.sh` | the hook: classifies every prompt into `log.jsonl`; `cx:` prompts also show the verdict and block |
| `prompt.md` | the classification rules |
| `log.jsonl` | every classification, git-ignored because it holds prompt text |

`classify` sets `HARNESS_CLASSIFYING=1` before it calls `claude -p`. That
nested call fires the hook again; the hook exits at once when it sees the
variable. Remove the guard and it loops forever.

## Tests

```bash
tests/hook_test.sh      # exact, classifier stubbed
tests/classify_test.sh  # exact, claude stubbed
tests/run.sh            # real model, 15 labelled prompts, ~2 min
```

`tests/run.sh` passes when the model matches on at least 12 of 15 and no
verdict is more than one tier off. Fix misses in `prompt.md`, never by
relabelling a case.

## Install

The hook is registered in `~/.claude/settings.json` under
`hooks.UserPromptSubmit` with `"timeout": 60`, well above the classifier's own
45s budget so a hook killed before it prints its block JSON can't let the
prompt run unclassified. To turn it off, delete that entry.

## Next stages

1. Dispatcher — stop blocking; hand the verdict to the main session, which
   dispatches a subagent with that model.
2. Agent choice — add an `agent` field to the verdict.
3. Superpowers — run `classify` before every subagent dispatch.
