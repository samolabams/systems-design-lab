# Multi-Region, Disaster Recovery & Backups

**Track:** Foundations
**Study role:** Advanced — study after availability, replication, and failure modes are understood.
**Prerequisites:** [Replication and failover](/modules/replication-failover/)

## Outcome

After this module, you should be able to explain RPO and RTO,
compare active-passive and active-active recovery strategies, and distinguish
replication from backup by performing a restore drill. You should also be able
to point at a recovery procedure and identify exactly where data loss can occur,
where downtime begins, and which copy is trusted during restore.

## What you will build or run

1. A disaster-recovery drill that separates backup from replication.
2. A simulated destructive change and a recovery path.
3. RPO and RTO reasoning for how much data loss and downtime are acceptable.
4. A checklist for deciding when multi-region complexity is justified.

## Why this matters

Single-region deployment is the default elsewhere in the lab. This module asks a
disaster-recovery question: **what happens when an entire region, or a mistaken
`DELETE`, removes critical data?** Replication can improve *availability*, but it
does **not** by itself provide *recoverability*. A tested restore procedure is
what separates a temporary outage from permanent data loss.

The important mental split is live redundancy versus historical recovery. A
replica is useful when a machine dies. A backup is useful when the live data is
wrong. Those failures feel similar during an incident because users cannot get
the data they need, but the recovery path is different: fail over to a healthy
copy for infrastructure failure; restore an older copy for logical corruption.

## Concept

- **RPO** (Recovery Point Objective) — how much data the system can afford to lose
  (maps to replication lag / backup interval).
- **RTO** (Recovery Time Objective) — how long recovery may take.
- **Topologies** — the shapes regions can take. *Active-passive* keeps a
  **warm standby**: a second region that is running and up to date but does not
  serve traffic until failover. *Active-active* has every region serving reads
  and writes at once. *Multi-primary* lets several regions accept writes, which
  requires a conflict-resolution policy when two regions write the same record.
- **Geo-replication cost** — crossing regions adds 80–150 ms of round-trip time
  (RTT, estimation). Keeping data *strongly* consistent across that distance is
  expensive, so most systems replicate **asynchronously**: changes land in the
  other region after a short delay, which is eventual consistency (consistency models).
- **Replication ≠ backup** — a bad `DELETE` replicates **instantly** to every
  copy. The system needs *point-in-time backups* (snapshots that can rewind to a moment
  before the mistake) that a human operator's error cannot propagate to.

## How it works

The central idea is that replication is not backup. The drill takes a backup,
then applies a destructive write that replicates to the standby before it is
detected. The replica therefore cannot recover the deleted data. Only the
**out-of-band backup** (a copy kept off the live replication path, so corruption
cannot reach it) can. An
optional extension adds injected latency (`tc`, Linux traffic control /
toxiproxy, a network-fault injector) so the standby behaves like a real second
region with visible lag (RPO).

## Run

This drill reuses the `replication-failover` profile because the backup and
restore lesson needs the same Postgres primary/standby topology.

```bash
make replication-failover
./modules/multi-region-dr/demo.sh   # guided backup -> destroy -> restore drill
```


The demo runs the steps below and prints the measured RTO; to run them by hand:

### Drill: replication is not backup

```bash
# 1. backup (out-of-band — the recovery copy)
docker compose exec -T postgres-primary pg_dump -U app --data-only -t links app > /tmp/app.sql
# 2. simulate disaster: a bad delete (it replicates to the standby instantly!)
docker compose exec -T postgres-primary psql -U app -d app -c 'DELETE FROM links;'
# 3. restore from the backup (the replica cannot recover this data)
docker compose exec -T postgres-primary psql -U app -d app < /tmp/app.sql
```

## How to read the commands

The `pg_dump` command creates an out-of-band recovery copy. The `DELETE` command
simulates logical corruption. The restore command proves recovery comes from the
backup, not from the replica.

Read the drill as a timeline. Before the backup, there is no recovery point.
After `pg_dump`, the recovery point exists but may become stale. After `DELETE`,
replication spreads the mistake. During restore, the system trades downtime for
returning to a known-good state.

## How to read the output

If the standby loses the rows too, replication has faithfully copied the bad
write. If the restore brings the rows back, the backup has provided recovery.
The reported RTO is elapsed restore time; the RPO is how much data could be lost
since the last backup.

If the demo prints row counts before and after each step, treat them as evidence
about which copy is safe. A matching empty count on primary and standby proves
replication worked, but also proves replication cannot undo this class of
failure. Restored rows prove the backup was both present and usable.

## What to observe

1. After the `DELETE`, the **replica is also empty** — the bad write replicated
   instantly. Availability machinery did not protect the data.
2. The **backup** restores the rows — recovery came from the out-of-band copy,
   not the standby.
3. The achieved **RPO** equals how stale the last backup was; the **RTO** equals
   how long the restore took. Both are measurable, not aspirational.

For each step, write one sentence in this form:

```text
This step proves _____ because the trusted recovery copy is _____.
```

## What you learned

- Replication is not the same thing as backup.
- RPO describes acceptable data loss; RTO describes acceptable recovery time.
- Multi-region designs trade cost and complexity for resilience to larger failures.
- Recovery plans should be practiced before a real outage.

## Practice experiments

1. Decide the maximum acceptable RPO for a payments table versus an analytics
  table.
2. Explain why a read replica cannot undo a bad `DELETE`.
3. Sketch how backup frequency changes storage cost and data-loss risk.

## Trade-offs

- Async geo-replication gives low-latency reads and a non-zero RPO; synchronous
  cross-region gives RPO≈0 but pays the full RTT on every write.
- Backups cost storage and discipline (untested backups are not backups) — but
  they're the only defense against logical corruption that replicates.
- Active-active maximizes availability but requires write-conflict resolution;
  active-passive is simpler and usually enough.

## Next steps

- [Availability](/modules/availability/) for reliability math.
- [Replication and failover](/modules/replication-failover/) for local failover behavior.
- [Observability](/modules/observability/) for detecting and diagnosing outages.

## Further reading

- AWS, "Disaster Recovery options in the cloud" (RPO/RTO, the four strategies):
  https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html
- PostgreSQL, "Continuous Archiving and Point-in-Time Recovery (PITR)":
  https://www.postgresql.org/docs/current/continuous-archiving.html
- Google SRE Book — "Data Integrity: What You Read Is What You Wrote":
  https://sre.google/sre-book/data-integrity/

## Cleanup

```bash
make reset
```
