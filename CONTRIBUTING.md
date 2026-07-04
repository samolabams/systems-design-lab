# Contributing to the Systems Design Lab

Thanks for your interest in improving the lab. It's a hands-on, runnable
guide for systems design, so the bar for a contribution is simple: **it
should run, and it should demonstrate something.** This guide explains how to get set
up, the conventions the repo follows, and how to propose a change.

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Fix or sharpen a module** — clearer explanation, a better `demo.sh`, a more
  honest failure scenario.
- **Add a module** — introduce a focused concept, a runnable scenario when
  appropriate, and links to related modules.
- **Add an app implementation** — a new runtime (Go, Python, Rust, ...) that
  satisfies the [app contract](README.md#application-contract).
  See [apps/README.md](apps/README.md).
- **Improve docs** — typos, broken links, and clarifications are all welcome.

## Getting set up

1. Install the prerequisites in [System requirements](README.md#system-requirements).
2. Fork and clone the repo.
3. Verify the base system runs before changing anything:
   ```bash
   cp .env.example .env
   make base
   curl localhost:8080/health   # {"host":"…","role":"app"}
   make reset
   ```

## Repository conventions

These are load-bearing — please keep them consistent.

- **Folder name == Make target.** A module in `modules/async-queues/` is run
  with `make async-queues`. If the module adds infrastructure, the folder name
  also matches the Compose profile. Base-backed modules keep the Make target
  without adding a profile.
- **One `docker-compose.yml`, profile-gated.** New services attach to the
  `backend` network (and `frontend` only if the gateway must reach them).
  Databases stay off the host (the DMZ rule).
- **Infrastructure is example-agnostic.** `infra/` holds reusable infra config
  (gateway, database, queues, observability). App- or demo-specific files belong
  with the app in `apps/`, not in `infra/`.
- **Every module ships a `demo.sh`** that boots the needed profiles, drives the
  scenario, and is safe to re-run. Reuse helpers in `scripts/`.
- **Comment the *why*.** Config files explain the reasoning behind non-obvious
  settings (see the existing `infra/**` configs as the standard to match).
- **App code** is CommonJS Node, MVC + repository layout; keep entrypoints thin
  and match the runtime used by the existing Dockerfiles. See
  [apps/README.md](apps/README.md).

## Making a change

1. Create a branch: `git checkout -b m6-mongo-replica-sets` (use a descriptive
   name).
2. Make your change and **run it locally**:
   - `docker compose config --quiet` — the compose file is valid.
   - `docker compose build <service>` — affected images build.
   - The relevant `make <profile>` boots and the module's `demo.sh` passes.
   - For app changes, `node --check` each file you touched.
3. Keep commits focused and write a clear message explaining *why*.
4. Open a pull request describing **what** changed, **why**, and **how you
   verified it** (the commands you ran). Link the module or issue it relates to.

## Pull request checklist

- [ ] `docker compose config --quiet` passes.
- [ ] Affected services build and boot; the demo runs end-to-end.
- [ ] Folder name and Make target match; profile-backed modules also match the
  Compose profile.
- [ ] No app/demo-specific files added under `infra/`.
- [ ] Docs updated (README/INSTRUCTIONS/module README) if behavior or layout
      changed.
- [ ] No secrets or real credentials added.

## Reporting bugs & proposing modules

Open an issue describing the scenario, the command you ran, what you expected,
and what happened (include logs). For a new module, sketch the concept it
demonstrates and the failure it makes observable — that framing is the heart of the
lab.

## Reporting security issues

Please do **not** open public issues for security vulnerabilities. Follow
[SECURITY.md](SECURITY.md) instead.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
