-- Create the replication role + a replication slot the load balancing streaming replica uses.
-- Runs once on first init of postgres-primary.

-- md5 so PgBouncer / standby auth match the server (see 00-auth.sql).
SET password_encryption = 'md5';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator';
  END IF;
END
$$;

SELECT pg_create_physical_replication_slot('replica_slot')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot'
);
