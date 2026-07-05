# Summary

Describe what changed and which module, app, or infrastructure area it affects.

## Why

Explain the problem this solves or the concept this improves.

## What changed

- 

## Validation

List the commands you ran and the result.

- [ ] `docker compose config --quiet`
- [ ] Affected services build and boot
- [ ] Relevant `make <profile>` target runs
- [ ] Relevant `demo.sh` runs end-to-end
- [ ] App or demo JavaScript passes `node --check`
- [ ] Documentation links and examples were checked

## Checklist

- [ ] Folder name and Make target match
- [ ] Profile-backed modules match the Compose profile
- [ ] No app/demo-specific files were added under `infra/`
- [ ] Docs were updated if behavior, commands, layout, or terminology changed
- [ ] No secrets or real credentials were added
- [ ] Security-sensitive changes avoid public vulnerability details

## Related issue or module

Link the issue, module, or design area this PR relates to.