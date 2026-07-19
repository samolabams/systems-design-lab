---
layout: home

hero:
  name: Systems Design Lab
  text: Learn systems design by running real infrastructure.
  tagline: Short lessons, Docker Compose profiles, guided demos, and capstone design exercises.
  actions:
    - theme: brand
      text: Start the Guide
      link: /guide/
    - theme: alt
      text: Browse Modules
      link: /modules/

features:
  - title: Runnable Lessons
    details: Start only the services a module needs, run its demo script, and observe the behavior directly.
  - title: Real Building Blocks
    details: Work with gateways, databases, caches, queues, event streams, object storage, vector search, and observability.
  - title: Design Practice
    details: Use the same concepts to work through end-to-end capstones like TinyURL, news feeds, chat, and rate limiters.
---

## Quick Start

```bash
cp .env.example .env
make base
curl http://localhost:8080/api/health
```

Then choose a lesson from the [module guide](/modules/).