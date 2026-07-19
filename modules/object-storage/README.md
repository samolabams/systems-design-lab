# Object Storage

**Track:** Components
**Study role:** Specialized - include when designs require large blobs, uploads, downloads, or media delivery.
**Prerequisites:** none

## Outcome

After this module, you should understand object storage as a general component
for durable blob storage, not as a database replacement. You should be able to
explain:

1. Why large blobs usually do not belong in relational database rows.
2. What object storage does: stores bytes as objects addressed by bucket and key.
3. What buckets, object keys, metadata, S3-compatible APIs, and presigned URLs are.
4. Why clients often upload or download objects directly instead of sending bytes
   through the application server.
5. How object storage, database metadata, application authorization, and CDN
   delivery fit together.
6. Why object storage is not a good fit for row-level transactions, joins, or
   low-latency mutable records.

## What you will build or run

By the end of this module, you will have a local object-storage environment with:

1. A private bucket that stores objects by bucket and key.
2. Several uploaded objects that can be listed by key and inspected by size.
3. A failed unsigned request that proves private objects are not public by
   default.
4. A working presigned URL that grants short-lived read access to one object.
5. A clear split between the object store, application authorization, and the
   database metadata that a real system would keep separately.

## Why this matters

**Object storage is a storage architecture for durable, API-addressable objects:
bytes plus metadata identified by a bucket and key.** A blob is opaque byte
content such as an image, video, PDF, backup,
export, log archive, user upload, or analytics dataset. The application
usually needs to store, retrieve, authorize, and serve those bytes, but it does
not need relational joins or row-level transactions over the bytes themselves.

Relational databases are excellent for structured records, constraints,
transactions, and indexed queries. They are usually the wrong home for large
binary objects. Putting large blobs in database rows can increase backup size,
hurt cache efficiency, stress replication, and make the database spend resources
moving bytes instead of protecting structured state.

Object storage does not replace the database. The database still stores durable
application metadata, ownership, permissions, object keys, and business state.
The object store stores the bytes.

The concept is independent of any one storage product. The lab uses MinIO as a
local S3-compatible implementation so buckets, object keys, private access, and
presigned URLs are visible. [Edge caching](../edge-caching/README.md)
shows how a CDN or edge cache can sit in front of object storage for delivery.
[Vector stores](../vector-store/README.md) solve a different problem: similarity
search over embeddings, often with object storage holding the original blobs.

## Concept

Object storage stores data as **objects** in a flat namespace. Each object is
addressed by two main identifiers:

```text
bucket + object key -> bytes plus metadata
```

The bucket is a top-level container. The object key is the name of one object
inside that bucket. Keys may look like paths, such as `users/42/avatar.png`, but
object storage is not a traditional filesystem. The slash is just part of the
key name unless the client or console chooses to display it like folders.

Common object storage terms:

- **Object** - stored bytes plus metadata, addressed by a key.
- **Bucket** - a named container for objects.
- **Object key** - the unique name of an object within a bucket.
- **Metadata** - attributes stored with the object, such as content type, size,
  checksum, or custom tags.
- **S3-compatible API** - an HTTP API modeled after Amazon S3, widely supported
  by cloud providers, storage systems, and tools.
- **Presigned URL** - a time-limited URL that carries authorization in the URL
  signature, allowing a client to upload or download one object without knowing
  storage credentials.
- **Multipart upload** - splitting a large object into parts so failed chunks can
  be retried without restarting the whole upload.
- **Origin** - the source a CDN reads from. Object storage is often the origin
  for CDN-served images, videos, downloads, and static assets.

The typical blob-serving path separates metadata from bytes:

```text
database stores: owner, permissions, object key, content type, status
object store stores: the bytes
client receives: a URL or redirect that lets it fetch bytes from storage/CDN
```

That separation keeps the application and database out of the high-volume byte
transfer path. The app can decide whether a user is allowed to access an object,
then hand out a short-lived presigned URL so the client talks directly to the
object store.

## How it works

The general roles are represented by local lab components:

| General role | Lab implementation |
|---|---|
| object store | MinIO, an S3-compatible object store |
| object storage client | `mc`, the MinIO command-line client |
| unprivileged application client | the URL-shortener `app` container |
| structured source of truth | Postgres primary, for metadata in real systems |
| CDN delivery layer | edge cache, described in [edge caching](../edge-caching/README.md) |

The `object-storage` profile adds MinIO to the base stack. The demo runs the
`mc` client as a temporary container on the backend network. It creates a private
bucket, stores several objects, lists them, and shows that an unsigned request is
refused.

Then the demo generates a presigned URL. The app container does not hold MinIO
credentials. It can still fetch the object through the presigned URL because the
URL itself contains a time-limited signature. That proves the core access pattern:
the application can authorize access without proxying the bytes.

The signature in a presigned URL is the authorization proof. Anyone who has the
URL can use it until it expires, so treat it like a short-lived bearer token
scoped to one object and operation.

When reading this module, keep these layers separate:

```text
database      -> durable metadata, ownership, permissions, object keys
object store  -> durable blob bytes addressed by bucket and key
CDN           -> cached delivery layer in front of the object store
application   -> authorization, metadata writes, presigned URL issuance
```

If the design is confusing, first ask what kind of data is being handled. If it
is structured state, it probably belongs in the database. If it is large opaque
bytes, it probably belongs in object storage. If it is cached delivery close to
users, it belongs in the CDN or edge layer from edge caching.

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the object storage profile:

```bash
make object-storage
```

Then run the guided demo:

```bash
./modules/object-storage/demo.sh
```

The demo pauses between steps. At each step, first read the question, then read
the command, then inspect the output. The goal is not to memorize MinIO syntax;
the goal is to connect each command to one object-storage idea.

To run without pauses:

```bash
AUTO=1 ./modules/object-storage/demo.sh
```

The MinIO console is published at `http://localhost:9101` by default. The local
lab credentials are `minioadmin` / `minioadmin` unless overridden by environment
variables.

## How to read the commands

Most object storage commands in the demo use `mc`, the MinIO client:

```bash
MC mb local/blobs
```

Read that as:

| Part | Meaning |
|---|---|
| `MC` | demo helper that runs the MinIO client in a temporary container |
| `mb` | make bucket |
| `local` | the configured alias for the MinIO endpoint |
| `blobs` | the bucket name |

Listing objects has this shape:

```bash
MC ls --recursive local/blobs
```

Read that as: list every object key under the `blobs` bucket and show object
metadata such as size and timestamp.

Generating a presigned URL has this shape:

```bash
MC share download local/blobs/report.txt --expire=3m
```

Read that as: create a signed download URL for one object, valid for 3 minutes.
The URL grants access to that object without exposing the MinIO username or
password.

Changing one part changes the question. `MC cat` reads object bytes. `MC ls`
lists object metadata. `MC share download` creates time-limited access.

## How to read the output

An object listing line usually shows a timestamp, size, and key, for example:

```text
2026-07-02 10:00:00 UTC    43B report.txt
```

Read that as:

| Field | Meaning |
|---|---|
| timestamp | when the object was last written |
| size | how many bytes the object contains |
| key | the object name inside the bucket |

An unsigned request to a private object should return an authorization failure,
commonly `403 Forbidden`. That means the object exists, but the caller did not
provide credentials or a valid signature.

A presigned URL output contains a long URL with query parameters. Those query
parameters are the signature and expiry information. Anyone who has that URL can
use it until it expires, so treat it like a short-lived bearer token.

## What to observe

1. **Bucket and key namespace** - objects in MinIO are addressed by bucket and
   key, not by relational table and row.
2. **Bytes stay out of the database** - object sizes are tracked by MinIO; the
   database does not store the blob bytes.
3. **Private by default** - an unsigned request to a private object returns
   `403 Forbidden`.
4. **Presigned URLs delegate access** - a client without storage credentials can
   download one object because the URL carries a time-limited signature.
5. **Application stays off the byte path** - the app can authorize access and
   hand out a URL without streaming the object itself.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves the bucket is private because the unsigned request returns 403.
```

## What you learned

- Object storage stores byte blobs as objects addressed by bucket and key.
- Keys can look like filesystem paths, but the object store treats them as names
   in a flat namespace.
- Private access is the default posture for this lab's bucket, so unsigned reads
   fail.
- Presigned URLs delegate access to one operation on one object for a limited
   time.
- The database should keep ownership, permissions, object keys, and workflow
   state; the object store should keep the bytes.

## Practice experiments

After the guided demo, make one change at a time and predict the effect before
running the command again:

1. **Add another object.** Pipe a new text file into `local/blobs`, list the
   bucket, and identify the new key and byte size.
2. **Change the presigned URL lifetime.** Generate a URL with a shorter expiry,
   such as `--expire=1m`, and explain why shorter lifetimes reduce exposure.
3. **Try an unsigned read for another object.** Confirm that private access rules
   apply to each object, not only `report.txt`.
4. **Classify data placement.** Decide whether each item belongs in a database or
   object store: profile photo bytes, profile owner ID, video file, invoice
   status, backup archive.
5. **Add CDN reasoning.** Explain how an edge cache would reduce repeated
   downloads for a public object.

Return each experiment to its original state before moving to another module, or
reset the whole lab deliberately.

## Trade-offs

- **Object storage is not a relational database.** It is excellent for durable
  blobs, but not for joins, row-level transactions, or low-latency mutable rows.
- **Presigned URLs are bearer tokens.** Anyone with the URL can use it until it
  expires; keep lifetimes short and scope each URL to one object and operation.
- **Direct-to-storage upload shifts responsibility.** The app avoids byte
  transfer, but it must still validate metadata, ownership, object size, content
  type, and post-upload state.
- **Eventual consistency can appear.** A freshly written object may briefly be
  unavailable in some storage systems or regions. Design read-after-write
  behavior where it matters.
- **Cost shape changes.** Object storage is low-cost for stored bytes, but
  request volume, egress, lifecycle retention, and CDN behavior affect total
  cost.

## Next steps

- Put [edge caching](../edge-caching/README.md) in front of object storage and
   reason about repeated downloads.
- Compare this module with [databases](../databases/README.md) and decide which
   fields belong in structured metadata versus blob storage.
- Use the [API design](../api-design/README.md) module to think through upload
   and download API shapes for direct-to-storage workflows.

## Further reading

- AWS, "Amazon S3 - how it works":
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html
- MinIO docs: https://min.io/docs/minio/linux/index.html
- AWS, "Sharing objects with presigned URLs":
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html

## Cleanup

```bash
make reset
```
