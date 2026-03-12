# Spec Kit in aictx

`aictx` supports a hybrid Spec Kit model:
- `aictx` remains the runtime, context manager, and session/finalize layer
- Spec Kit-compatible artifacts provide explicit feature intent and planning artifacts

## Why this exists

The main value of Spec Kit is not only the philosophy. It is also the artifact model:
- a durable constitution
- feature specs
- plans
- tasks
- consistency checks across those files

`aictx` adopts that model without making the whole project depend on upstream tooling for the default workflow.

## Commands

```bash
aictx spec-kit install
aictx spec-kit sync
aictx spec-kit status
aictx spec-kit uninstall
```

Related commands:

```bash
aictx constitution
aictx specify 001-feature-name
aictx analyze 001-feature-name
```

## Modes

`aictx spec-kit install` supports two modes.

### `bundled`

Default mode.

`aictx` installs a Spec Kit-compatible layout using templates shipped inside the repository.

Use this when you want:
- stable behavior
- no network dependency
- a Spec Kit-style artifact workflow without coupling project setup to upstream availability

### `upstream`

Opt-in mode.

`aictx` fetches templates from the official `github/spec-kit` repository and records the pinned ref in `.aictx/spec-kit.json`.

Use this when you want:
- closer compatibility with upstream templates
- explicit version pinning
- controlled syncs to newer upstream refs

## What gets installed

The managed layout is:

```text
.specify/
  memory/
    constitution.md
specs/
  <feature-id>/
    spec.md
    plan.md
    tasks.md
    meta.json
```

Metadata and managed template cache stay in:

```text
.aictx/spec-kit.json
.aictx/spec-kit-templates/
```

`aictx` continues to use `.aictx/` for project memory such as `DIGEST.md`, `CONTEXT.md`, and session history.

## Behavior

Without Spec Kit installed:
- `constitution` uses `.aictx/constitution.md`
- `specify` uses `.aictx/specs/<slug>/`

With Spec Kit installed or an active `.specify/` + `specs/` layout:
- `constitution` uses `.specify/memory/constitution.md`
- `specify` uses `specs/<slug>/`

This lets `aictx` work in both local-only and Spec Kit-compatible projects.

## Install examples

Bundled:

```bash
aictx spec-kit install
```

Upstream:

```bash
aictx spec-kit install --source upstream --ref main
```

Check status:

```bash
aictx spec-kit status
```

## Sync behavior

`sync` refreshes the managed templates and metadata.

- In `bundled` mode, templates are refreshed from the local `aictx` copy
- In `upstream` mode, templates are fetched again from the pinned ref or a new `--ref`

`sync` does not rewrite existing feature specs or tasks.
It only refreshes managed templates and can refresh `constitution.md` when `--force` is used.

## Uninstall behavior

`aictx spec-kit uninstall` removes:
- `.aictx/spec-kit.json`
- `.aictx/spec-kit-templates/`

It does not delete:
- `.specify/`
- `specs/`
- existing feature artifacts

That makes uninstall non-destructive. It removes management metadata, not project work.

## Recommended flow

If you want explicit feature artifacts:

```bash
aictx spec-kit install
aictx constitution
aictx specify 001-login-rate-limit
aictx analyze 001-login-rate-limit
aictx run --spec 001-login-rate-limit
```

If you prefer the simpler local-only flow, keep using:

```bash
aictx init
aictx constitution
aictx specify 001-login-rate-limit
aictx run --spec 001-login-rate-limit
```
