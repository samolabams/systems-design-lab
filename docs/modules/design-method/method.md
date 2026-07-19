# Design Method Design-Method Rubric

Apply this to every Capstones capstone. Score each row mid / senior / staff.

| Dimension | Mid | Senior | Staff |
|---|---|---|---|
| **Requirements** | lists functional reqs when prompted | separates functional vs non-functional; names the dominant constraint | drives ambiguity; sets scope & success metric |
| **Estimation** | rough QPS/storage | peak factor, read:write, hot-set size | ties numbers to a build/buy/scale decision |
| **High-level design** | correct boxes & arrows | clean data flow; clear service boundaries | failure domains & blast radius considered |
| **Component choice** | reasonable, mostly justified | justifies each; knows the alternatives | picks the *minimum* that meets reqs (when not to scale) |
| **Scaling** | adds replicas/cache when asked | finds the real bottleneck first | sequences scaling moves; migration path |
| **Consistency** | aware of strong vs eventual | maps model to mechanism (consistency models) | reasons about partitions, ordering, dedup |
| **Trade-offs** | mentions one | quantifies several | owns them; states what's deferred & why |
| **Operability** | "add monitoring" | RED/USE, SLOs, alerts (availability) | error budgets, rollback, DR (multi-region DR) |

## Capstone checklist

- [ ] Requirements + the single dominant non-functional constraint stated.
- [ ] Estimates (estimation) justify each piece of machinery (no premature scaling, when not to scale).
- [ ] High-level diagram + the exact lab profiles used.
- [ ] Bottleneck identified and addressed with a named component.
- [ ] Consistency model named (consistency models) and its cost acknowledged.
- [ ] Trade-offs and deferred work explicit.
- [ ] A `demo.sh` boots the profile set and drives load + a failure.
