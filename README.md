# aictx (token-optimized)

Per-project persistent AI context runner that supports **Codex CLI**, **Claude Code CLI**, and **Gemini CLI**.

## Why token-optimized?
By default, `aictx run` uses `prompt_mode=paths`:
- The initial prompt is tiny and points the model to read local files.
- The model reads `.aictx/DIGEST.md` first (compact working memory).
- Detailed docs remain on disk (CONTEXT/DECISIONS/TODO/sessions) but are not inlined into the prompt.

If you want the previous (token-heavy) behavior, set:
```json
{ "prompt_mode": "inline" }
```
in `.aictx/config.json`.

## Install (macOS)

```bash
git clone https://github.com/<you>/aictx ~/.aictx-tool
mkdir -p ~/.local/bin
ln -sf ~/.aictx-tool/bin/aictx ~/.local/bin/aictx

grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Use (inside a project repo)

```bash
aictx init
aictx run                 # engine auto (prefers codex > claude > gemini if installed)
aictx run --engine claude  # choose Claude
aictx run --engine gemini  # choose Gemini
```

### Gemini CLI notes
- `aictx init` creates a repo-root `GEMINI.md` if missing. Gemini CLI loads it automatically for persistent project instructions.

### Background finalize safety
- `aictx run` writes a pending job under `.aictx/pending/` **before** starting the session.
- A best-effort `trap` finalizes on normal exits.
- For crashes/terminal closes, run a watcher:

```bash
aictx watch
```

On macOS, you can run it as a LaunchAgent:

```bash
aictx install-launchd
```

## Legacy migration
If a project contains `.codex-context/`, `aictx init` migrates it into `.aictx/` and moves the legacy folder to a timestamped backup.
