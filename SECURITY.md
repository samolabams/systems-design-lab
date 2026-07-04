# Security Policy

## Supported Scope

This repository is a local practice lab. The configurations, credentials, exposed
ports, and container images are intended for local experimentation only. They are
not supported as a production deployment baseline.

Security fixes are accepted for the current main branch. Older snapshots, forks,
or local modifications are best-effort.

## Reporting a Vulnerability

Please do **not** open a public issue for a security vulnerability.

Report vulnerabilities privately through GitHub private vulnerability reporting
if it is enabled for the repository, or contact the maintainers through the
private channel listed by the project owner.

A useful report includes:

- the affected file, service, or module;
- the command needed to reproduce the issue;
- the expected impact;
- any relevant logs or container output.

## Local Lab Notes

- Do not deploy this Compose stack directly to a public network.
- Do not replace the example credentials with real credentials.
- Keep databases and infrastructure services on the internal Docker network.
- Run `make reset` after experiments when you want containers and lab volumes
  removed.
- After changing base images or security-sensitive configuration, rerun
  `docker compose config --quiet` and the relevant validation command.
