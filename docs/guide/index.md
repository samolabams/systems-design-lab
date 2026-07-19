# Guide

Systems Design Lab is a local practice environment for core systems-design
ideas. Each module introduces a concept, starts the smallest useful set of local
services, and gives you commands that make the behavior observable.

## How It Works

Most runnable modules follow this shape:

```bash
make <module-name>
./modules/<module-name>/demo.sh
```

For example:

```bash
make caching
./modules/caching/demo.sh
```

Use `AUTO=1` to run many demos without pauses:

```bash
AUTO=1 ./modules/caching/demo.sh
```

## Base Architecture

```text
client -> edge gateway -> application service -> data access layer -> durable store
```

The concrete base lab implements that path as:

```text
curl/browser -> Nginx gateway -> URL-shortener app -> database access layer -> relational database
```

The repo uses Docker Compose profiles so lessons add only the infrastructure
they need. That keeps the local footprint small and keeps each module focused on
one design mechanism.

## Requirements

- Docker Desktop or Docker Engine with Compose v2
- `make`
- `curl`
- `bash`
- Node.js for local documentation commands and a few scripts

Optional but useful:

- `jq` for JSON output
- `k6` for local load testing, though `make load` runs it through Docker

## Common Commands

```bash
make help                         # list targets
make base                         # start the base request path
make scale N=3                    # scale stateless app replicas
make load                         # run the k6 smoke load through the gateway
make <module-name>                # start services for one module
make validate-profile PROFILE=dns # validate one runnable module
make validate                     # validate runnable modules sequentially
make reset                        # stop containers and remove volumes
```

For the full repository README, see the source on GitHub.