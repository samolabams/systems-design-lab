# Vector stores and similarity retrieval

**Track:** Components
**Study role:** Specialized - include when designs require semantic retrieval, recommendations, image similarity, or similar-item search.
**Prerequisites:** none

## Outcome

After this module, you should understand a vector store as a specialized index
for similarity retrieval, not as a replacement for the primary database. You
should be able to explain:

1. What embeddings are and why systems store them.
2. What nearest-neighbor retrieval means.
3. Why vector databases use indexes optimized for similarity, not exact keys.
4. What metadata filters do alongside vector similarity.
5. Why vector retrieval is useful for semantic retrieval, recommendations, image
  similarity, duplicate detection, and similar-item search.
6. Why vector data is usually derived from source data and must be refreshed when
   the source or embedding model changes.

## What you will build or run

1. A local vector-store collection with inserted embeddings and payload metadata.
2. Similarity queries that return nearby items instead of exact key matches.
3. Examples that connect vector retrieval to recommendations, search, and duplicate detection.
4. A comparison between vector stores, databases, caches, and object storage.

## Why this matters

**A vector store is a database for finding similar items.** It stores numeric
representations of content, called embeddings, plus payload metadata. Instead of
looking up only exact keys, applications can ask for the nearest stored items to
a query vector. Traditional databases answer questions like "give me row 42" or
"find orders where status is paid." Object storage stores bytes. A vector store
answers a different question: "which stored items are closest to this query in
meaning or features?"

That question appears in modern systems: similar product recommendations,
semantic document retrieval, image similarity, duplicate detection, personalized
ranking, and similar-item discovery.

Vector stores do not replace the source of truth. The database still stores
metadata, ownership, permissions, and business state. Object storage still stores
large files. The vector store keeps embeddings and payload metadata optimized for
nearest-neighbor lookup.

The concept is independent of any one vector database. The lab uses Qdrant as a
local implementation so collections, distance metrics, payload filters, and
nearest-neighbor queries are visible in Docker Compose.

## Concept

An **embedding** is a list of numbers produced by a model. The numbers represent
meaning or features in a vector space:

```text
text/image/product -> embedding model -> [0.12, 0.88, 0.10, 0.02]
```

A vector store saves those vectors and retrieves nearby vectors:

```text
query item -> query embedding -> nearest stored embeddings -> matching payloads
```

Common vector-store terms:

- **Embedding** - a numeric vector produced from text, an image, audio, or another
  input.
- **Vector collection** - a named group of vectors with the same dimension and
  distance metric.
- **Dimension** - how many numbers are in each vector.
- **Distance metric** - the rule for comparing vectors, such as cosine
  similarity, dot product, or Euclidean distance.
- **Nearest-neighbor retrieval** - finding stored vectors closest to a query vector.
- **ANN** - Approximate Nearest Neighbor retrieval; trades exactness for speed and
  memory efficiency.
- **Payload / metadata** - structured fields stored with a vector, such as title,
  tenant, category, URL, or permission scope.
- **Metadata filter** - a filter applied before or during similarity retrieval, such
  as `category = systems` or `tenant_id = 42`.
- **Reranking** - rescoring retrieved candidates with business rules, model
  scores, freshness, or other signals.

Vector retrieval is powerful because semantically related items can be close even
when they do not share exact words. It is also risky because similarity is not
the same as correctness. Production systems usually combine vector retrieval
with metadata filters, authorization checks, ranking, reranking, and evaluation.

## How it works

The general roles are represented by local lab components:

| General role | Lab implementation |
|---|---|
| vector database | Qdrant |
| vector collection | `docs` |
| vectors | small hand-written 4-dimensional embeddings |
| payload metadata | title and category fields |
| vector query client | `curl` |

The demo creates a Qdrant collection with vectors of size 4 and cosine distance.
It upserts a few example points with payload metadata. The vectors are tiny and
hand-written so the math is visible. A real system would generate embeddings with
an embedding model and usually store many more dimensions.

The demo then queries with a vector. Nearby vectors return first. Finally,
it repeats the query with a metadata filter, proving that vector similarity and
structured filtering solve different parts of the retrieval problem.

Keep these layers separate:

```text
source database -> durable metadata, permissions, business state
object store    -> large original files, if any
embedding model -> converts source content into vectors
vector store    -> nearest-neighbor retrieval over vectors plus payload metadata
application     -> authorization, query construction, ranking, final response
```

## Real-world examples

Use vector retrieval when the query is about similarity rather than exact field
matches. The vector store narrows the candidate set; the application still owns
authorization, ranking, and final response construction.

| System | What gets embedded | Useful metadata filters | Why vector retrieval helps |
|---|---|---|---|
| Documentation search | paragraphs or sections | `document_id`, `section`, `tenant_id`, `permission_scope` | finds relevant text even when the query uses different wording |
| Product recommendations | product titles, descriptions, images, or behavior signals | `category`, `brand`, `price_band`, `in_stock`, `region` | finds similar or substitutable products beyond exact category matches |
| Image similarity | image feature vectors | `owner_id`, `content_type`, `created_at`, `review_status` | finds visually similar images, duplicates, or near-duplicates |
| Support ticket routing | ticket text and resolution summaries | `product`, `severity`, `customer_tier`, `language` | finds similar past cases and likely owning teams |
| Fraud or duplicate detection | account, listing, or transaction features | `tenant_id`, `country`, `risk_band`, `status` | surfaces records that look alike even when exact identifiers differ |

The common design pattern is:

```text
source record changes
-> generate or refresh embedding
-> upsert vector plus payload metadata
-> query by vector
-> filter by tenant, permission, category, or status
-> rerank and fetch source records before returning results
```

## Run

Run these commands from the repository root:

```bash
pwd
```

The output should end with:

```text
systems-design
```

Start the vector-store profile:

```bash
make vector-store
```

Then run the guided demo:

```bash
./modules/vector-store/demo.sh
```

To run without pauses:

```bash
AUTO=1 ./modules/vector-store/demo.sh
```

Qdrant is published at `http://localhost:6333` by default.

## How to read the commands

Creating a collection has this shape:

```bash
curl -X PUT http://localhost:6333/collections/docs \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":4,"distance":"Cosine"}}'
```

Read that as: create a vector collection where every vector has 4 numbers and
similarity is measured by cosine distance.

Upserting points has this shape:

```json
{
  "id": 1,
  "vector": [0.10, 0.90, 0.10, 0.00],
  "payload": { "title": "cache aside", "category": "systems" }
}
```

Read that as: store one vector plus structured metadata. The metadata is what the
application can display, filter, or use for authorization.

Querying by vector has this shape:

```json
{
  "vector": [0.12, 0.88, 0.10, 0.02],
  "limit": 3,
  "with_payload": true
}
```

Read that as: find the three stored vectors closest to the query vector and
return their payloads.

## How to read the output

A retrieval result contains an ID, score, and payload. Conceptually:

```text
id=1 score=0.999 title=cache aside category=systems
```

The exact score is less important than the ordering. Higher cosine score means
the stored vector is closer to the query vector. If `cache aside` and `job queue`
rank above `banana smoothie`, the query vector is closer to the systems-design
examples than to the food examples.

When a metadata filter is added, only matching payloads are eligible. If the
query vector is systems-like but the filter says `category = food`, the nearest
food vectors are returned instead. That proves vector similarity and structured
filtering are separate controls.

## What to observe

1. **Collections define vector shape** - all points in `docs` use the same
   dimension and distance metric.
2. **Vectors drive retrieval** - nearest vectors return before unrelated vectors.
3. **Payloads make results usable** - the vector is not enough for the UI; the
   payload carries title and category.
4. **Metadata filters constrain retrieval** - filters can enforce category, tenant,
   language, permission, or product constraints.
5. **The vector store is derived state** - source content and embedding model
   changes require re-embedding and updating the collection.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

## What you learned

- A vector store finds similar items by comparing numeric representations called embeddings.
- Similarity retrieval answers a different question from exact database lookup.
- Payload metadata helps filter or explain vector-search results.
- Vector stores usually complement databases and object storage rather than replacing them.

## Practice experiments

1. Add another point near the systems vectors and predict where it ranks.
2. Query with a food-like vector and confirm the food examples rise.
3. Add a metadata filter that excludes the best vector and explain why the second
   best eligible result appears.
4. Change the collection distance metric on paper and explain why all vectors
   would need to be interpreted consistently.
5. Design a retrieval payload with `document_id`, `chunk_id`, `tenant_id`, and
   `source_url` fields.

## Trade-offs

- **Similarity is not correctness.** Nearby vectors can be plausible but wrong;
  retrieval needs evaluation and often reranking.
- **Embeddings are derived data.** Model changes require re-embedding source
  content, which can be expensive.
- **Metadata filters matter.** Without tenant, permission, and category filters,
  vector retrieval can leak or mix data.
- **ANN trades accuracy for speed.** Approximate indexes make large collections
  fast but may miss the exact nearest vector.
- **Vector stores do not replace databases.** Keep business state and source of
  truth in the database; keep original files in object storage.

## Next steps

- [Object storage](../object-storage/README.md) for storing original blobs.
- [Databases](../databases/README.md) for durable metadata and ownership.
- [API design](../api-design/README.md) for exposing retrieval behavior to clients.

## Further reading

- Qdrant docs: https://qdrant.tech/documentation/
- Pinecone, "What is a vector database?":
  https://www.pinecone.io/learn/vector-database/
- Milvus docs: https://milvus.io/docs
- Weaviate docs: https://weaviate.io/developers/weaviate

## Cleanup

```bash
make reset
```
