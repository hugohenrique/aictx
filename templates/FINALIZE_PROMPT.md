Generate a SINGLE unified diff patch (git apply compatible). Output ONLY the diff, no commentary.

Files to update:
- .aictx/DIGEST.md (compact working memory; keep <= ~80 lines; bullets; no fluff)
- .aictx/CONTEXT.md (<= 30 lines; factual & stable only)
- .aictx/DECISIONS.md (append-only, dated)
- .aictx/TODO.md (actionable tasks only)
- {{SESSION_FILE}} (fill Objective / What was done / Decisions / Next steps)

Read the transcript from disk (source of truth):
{{TRANSCRIPT_FILE}}

Rules:
- Do not invent facts. If uncertain, write 'Unknown'.
- Prefer updating DIGEST.md rather than expanding other files.
- Keep changes minimal and correct.
