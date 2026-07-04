-- Force md5 password storage so PgBouncer (auth_type = md5) can log in to the
-- server. Postgres 16 defaults to scram-sha-256, which PgBouncer's md5 userlist
-- cannot satisfy ("wrong password type"). Re-set the app role's password under
-- md5 encryption. Runs first (00-) on initial init.
SET password_encryption = 'md5';
ALTER USER app WITH PASSWORD 'app';
