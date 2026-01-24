# Token Optimization Guide

This document explains aictx's token optimization features and how they work.

## Overview

aictx implements aggressive token optimization to minimize API costs while maintaining context quality. Three phases have been implemented:

**Phase 1: Template Minification** (300-500 tokens saved/run)
**Phase 2: Lazy Loading + Caching** (100-350 tokens saved/run)
**Phase 3: Intelligent Compression** (50-200 tokens saved/run)

**Total savings: 450-1050 tokens per run (40-70% reduction)**

---

## Phase 1: Template Minification

### What Changed
- **PROMPT.md**: Compressed from 18 to 13 lines using semantic abbreviations
- **DIGEST.md**: Ultra-compact format; reduced limit from 80 to 60 lines
- **CONTEXT.md**: Compressed to 7 lines; reduced limit from 30 to 20 lines
- **FINALIZE_PROMPT.md**: Removed redundant prefixes and condensed

### Semantic Abbreviations Used
- `SWE` → Senior Software Engineer
- `impl` → implementation
- `refac` → refactoring
- `deps` → dependencies
- File paths: `.aictx/` prefix removed where clear from context

### Session Cleanup
New command available:
```bash
aictx cleanup
```

This command:
- Archives sessions older than 30 days
- Keeps only the 5 most recent sessions
- Removes old pending artifacts (.done.json >7d, orphaned .json >3d)

---

## Phase 2: Lazy Loading + Caching

### Lazy File Loading

aictx now intelligently skips loading optional files based on content and recency:

#### TODO.md Skip Logic
**Skipped when:** File has fewer than 3 non-empty, non-comment lines (template only)

**Token savings:** ~79 tokens when skipped

**Example skipped TODO.md:**
```markdown
# TODO

```

#### DECISIONS.md Skip Logic
**Skipped when:** No decision entries from the last 7 days

**Token savings:** ~214 tokens when skipped

**Force inclusion:** Add a decision with today's date:
```markdown
## 2026-01-20
- Your decision here
```

#### Previous Session Skip Logic
**Skipped when:** Session file is older than 3 days

**Token savings:** ~200-500 tokens when skipped (variable)

**Override:** None - designed to prevent stale context

### Conditional Context Caching

CONTEXT.md is cached to avoid redundant loading:

#### Cache Behavior
- **Cache file:** `.aictx/.context_hash` (auto-managed, gitignored)
- **Cache validity:** 24 hours
- **Invalidation:** Automatic when CONTEXT.md content changes (MD5 hash check)

#### When CONTEXT.md is Loaded
1. First run (no cache exists)
2. Cache older than 24 hours
3. CONTEXT.md content changed since last cache

#### When CONTEXT.md is Skipped
- Cache exists, is <24h old, AND content unchanged
- **Token savings:** ~65 tokens
- **Note added to prompt:** "(CONTEXT.md cached, read if needed)"

#### Manual Cache Invalidation
```bash
rm .aictx/.context_hash
```

---

## Optimization Impact by Mode

### Paths Mode (Default)
Paths mode sends file paths, not content. Optimizations reduce:
1. **Prompt overhead:** File paths omitted from optional list
2. **CLI reads:** Files not read by codex/claude/gemini CLIs

**Typical savings:** 100-150 tokens/run
**Maximum savings:** 358 tokens/run (all optional files skipped)

### Inline Mode
Inline mode embeds full file content. Optimizations skip entire file contents.

**Typical savings:** 150-350 tokens/run
**Maximum savings:** 400+ tokens/run (all optional files skipped)

---

## Best Practices

### Maximize Token Savings

1. **Keep TODO.md minimal** - Only list actionable tasks
2. **Clean up old decisions** - Archive decisions >30 days to separate file
3. **Run cleanup regularly** - `aictx cleanup` before important sessions
4. **Let CONTEXT.md stabilize** - Avoid frequent changes to maximize caching

### When to Bypass Optimizations

If you need to force-load files:

**TODO.md:** Add 3+ real tasks
```markdown
# TODO

- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
```

**DECISIONS.md:** Add recent dated entry
```markdown
## 2026-01-20
- Force load decision
```

**CONTEXT.md:** Delete cache
```bash
rm .aictx/.context_hash
```

---

## Monitoring Optimization Impact

### Check What's Loaded
Look at the generated prompt (visible in paths mode):
```
# aictx paths
Read: .aictx/PROMPT.md; .aictx/DIGEST.md (first). Optional: .aictx/DECISIONS.md (CONTEXT.md cached, read if needed)
```

Interpretation:
- ✅ TODO.md omitted (empty)
- ✅ CONTEXT.md cached (hash unchanged)
- ✅ DECISIONS.md included (recent entries)
- ✅ Previous session omitted (>3 days old)

### Debug Lazy Loading
```bash
# Check TODO line count
grep -Ev '^#|^$|^\s*$' .aictx/TODO.md | wc -l

# Check DECISIONS dates
grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' .aictx/DECISIONS.md

# Check CONTEXT cache
ls -lah .aictx/.context_hash
cat .aictx/.context_hash
```

---

## Phase 3: Intelligent Compression

### What Changed
Phase 3 implements automatic transcript compression and smart DIGEST delta updates.

#### Intelligent Transcript Compression
**Function**: `ai_compress_transcript()` in `lib/core.sh`

**Compression Layers**:

1. **Layer 1: Sanitization** (from Phase 1)
   - Strips ANSI/control characters
   - Collapses blank lines

2. **Layer 2: Error/Warning Deduplication**
   - Detects repeated errors: `Error: Connection timeout`
   - First occurrence: kept as-is
   - Subsequent: collapsed into `(repeated 3x)` format
   - **Savings**: ~20-50 tokens for repeated errors

3. **Layer 3: Readonly Command Deduplication**
   - Tracks outputs of readonly commands: `ls`, `cat`, `grep`, `git status`, etc.
   - Compares output hash with previous executions
   - Duplicate outputs: marked as `# [output omitted - unchanged from previous run]`
   - **Savings**: ~30-100 tokens when commands repeated

4. **Layer 4: Long Output Truncation**
   - Detects output blocks > 100 lines (e.g., `npm install`)
   - Keeps first 20 + last 20 lines
   - Middle summarized: `... [160 lines omitted] ...`
   - **Savings**: ~200-500 tokens for long outputs

**Integration**: Runs automatically after sanitization in `run_with_script_transcript()`

**Results**: Typical 15-30% transcript reduction (~50-200 tokens)

#### Delta-Based DIGEST Updates
**Functions**: `aictx_snapshot_digest()`, `aictx_build_finalize_prompt()` in `lib/prompt.sh`

**How It Works**:
1. **Before run**: Snapshot saved to `.aictx/.digest_snapshot`
2. **After run**: Finalize compares current DIGEST with snapshot
3. **Small changes** (< 15 words diff): Embed diff in finalize prompt
4. **Large changes**: Use standard paths reference (more efficient)

**Example Delta Prompt**:
```
DIGEST.md delta:
```diff
@@ -10,3 +10,4 @@
 - Recent improvement
+- New bullet point added
```

Update DIGEST.md: apply delta above
```

**Savings**: 0-50 tokens when applicable (automatic fallback when not beneficial)

**Note**: Delta only used when it saves tokens vs paths reference

---

## Token Cost Calculation

### Before Optimizations (baseline)
- Paths mode: ~100 tokens/run
- Inline mode: ~2000 tokens/run
- Finalize: ~150 tokens

### After Phase 1+2
- Paths mode: ~50-60 tokens/run (40-50% reduction)
- Inline mode: ~1150-1600 tokens/run (20-42% reduction)
- Finalize: ~100 tokens (33% reduction)

### After Phase 1+2+3
- Paths mode: ~40-50 tokens/run (50-60% reduction)
- Inline mode: ~1000-1400 tokens/run (30-50% reduction)
- Finalize: ~80-100 tokens (33-47% reduction)
- Transcript: 15-30% smaller (compression applied automatically)

### ROI Example (Sonnet 4.5 pricing)
Assuming 50 runs/month with inline mode:
- Before: 50 × 2000 = 100,000 tokens/month
- After: 50 × 1400 = 70,000 tokens/month
- **Savings: 30,000 tokens/month (~$0.36-0.90 depending on model)**

---

## Troubleshooting

### CONTEXT.md Always Reloading
**Symptom:** Cache invalidates every run
**Cause:** CONTEXT.md being modified during finalize
**Solution:** Ensure CONTEXT.md only contains stable facts

### TODO.md Not Loading When Needed
**Symptom:** Tasks exist but TODO.md omitted
**Cause:** Tasks might be in comments or empty lines
**Solution:** Ensure tasks are non-empty, non-comment lines

### Decisions Not Loading
**Symptom:** DECISIONS.md omitted but has content
**Cause:** All entries older than 7 days
**Solution:** Add recent dated entry (## 2026-01-XX)

---

## Summary

Phase 1+2 optimizations provide **40-60% token reduction** through:
- Template minification
- Lazy file loading
- Context caching

No configuration required - optimizations are automatic and transparent.

For maximum savings:
- Keep files minimal and clean
- Run `aictx cleanup` regularly
- Let CONTEXT.md stabilize for caching benefits
