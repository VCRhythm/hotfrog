# hotfrog

## Reporting Bugs to the Bug Loop

This project uses a local bug inbox (`.bugs/`) drained by a fixer loop (`/bugloop`).
Any agent that finds a bug it is not going to fix right now should file it there
instead of leaving it in chat:

```bash
python ~/.claude/skills/bugloop/scripts/bugloop.py add "one-line symptom" \
  --source claude-session \
  --context '{"file":"src/server/X.luau","line":123,"repro":"...","expected":"...","actual":"..."}'
```

- `--context` is free-form JSON; include the file and line, a repro, and expected vs actual.
- `--log path` attaches the tail of a log file. `--reopen b-...` links to an earlier entry.
- Equivalent HTTP: `POST http://127.0.0.1:8644/` with `{"note","source","context","log"}`
  (contract in `~/.claude/skills/bugloop/templates/CONTRACT.md`). Falls back to the CLI if
  the listener is down; the CLI never needs it.
- Do not edit `.bugs/inbox.jsonl` by hand. Read `.bugs/done.md` before filing to avoid
  duplicates. Dashboard for humans: `http://127.0.0.1:8644/`.
