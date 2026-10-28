# Semantic Search in Rails

**Ask the Rails Guides in your own words.** Keyword and vector search side by side, a cutoff that
can say *"Not covered in the Guides"*, and a retrieval eval that runs as a Minitest test.

![Rails 8.1](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)
![Ruby 3.4](https://img.shields.io/badge/Ruby-3.4-CC342D?logo=ruby&logoColor=white)
![PostgreSQL + pgvector](https://img.shields.io/badge/PostgreSQL-pgvector-4169E1?logo=postgresql&logoColor=white)
![Runs locally](https://img.shields.io/badge/runs-100%25%20locally-2E7D32)

Built for a 20-minute talk. No API keys, no cloud services, no network after the first model
download.

## What it shows

| Question | Keyword search | Vector search |
|---|---|---|
| `make sure a field is not left blank before saving` | Nothing: no passage has every word | **Validations › presence** (distance 0.49) |
| `after_commit` | Finds it: exact names are keyword's strength | Finds it too (0.43) |
| `best hiking trails in Patagonia` | Nothing | Five results anyway, all dimmed: **Not covered in the Guides** (0.73, past the 0.68 cutoff) |

Then in the terminal, the eval passes on 150-word chunks and fails on 30-word chunks.
The talk script is in [`docs/DEMO.md`](docs/DEMO.md), and the slides are in
[`docs/semantic-search-in-rails.pptx`](docs/semantic-search-in-rails.pptx).

## Quick start

You need Ruby 3.4, PostgreSQL with pgvector, and about 100 MB for the model cache.

```bash
brew install postgresql@18 pgvector   # or: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres pgvector/pgvector:pg17

bundle install
bin/rails db:prepare
git clone --depth 1 https://github.com/rails/rails vendor/rails   # the Guides, git-ignored

bin/rails guides:warmup            # download the embedding model once
bin/rails 'guides:ingest[150]'     # 4,743 chunks (first run: 79 s on an M-series Mac)
bin/rails 'guides:ingest[30]'      # 17,759 chunks (first run: 253 s), for the eval's "break it" run

bin/rails server                   # http://localhost:3000
```

> [!NOTE]
> `config/database.yml` uses port **5433** (Homebrew `postgresql@18`). Set `PGPORT=5432` for a
> default install or Docker.

Re-running `guides:ingest` is safe: unchanged chunks are skipped, and the task prints how many it
embedded.

## How it works

| Step | Where | What |
|---|---|---|
| **Chunk** | `GuideChunker` | Splits each guide at its headings, packs paragraphs up to N words, strips markdown noise |
| **Embed** | `EmbedChunkJob`, `Embedder` | 384-dim vectors from `all-MiniLM-L6-v2` via the `informers` gem; a content hash skips unchanged chunks |
| **Store** | `chunks` table | `vector(384)` column in Postgres, one row per chunk per `variant` (`w150`, `w30`) |
| **Search** | `ChunkSearch` | `keyword_search` (full-text), `vector_search` (cosine), `hybrid_search` (RRF), `semantic_search` (vector + cutoff) |
| **Measure** | `test/evals` | Hit rate@5 per strategy, plus out-of-scope rejection |

The page uses `w150` and shows keyword and vector search. Hybrid isn't on the page, but the eval
measures it.

## How the Rails Guides get into the database

1. **Source.** The Guides are markdown files in the Rails repo under `guides/source/`. Nothing is
   scraped from the website: `git clone --depth 1 https://github.com/rails/rails vendor/rails`
   (`vendor/rails` is git-ignored). Set `GUIDES_PATH` to read them from somewhere else.
2. **Run the task.** `bin/rails 'guides:ingest[150]'`, where the number is the max words per chunk.
   It reads every `guides/source/*.md` file (76 today, release notes included).
3. **Chunk** (`GuideChunker`):
   - Split at headings. The Guides write H1/H2 as setext (`Title` over a line of `=` or `-`) and
     H3+ as `###`; both count, and `#` lines inside fenced code don't. Each section keeps its
     heading path from H2 down, e.g. `Transaction Callbacks > Aliases for after_commit` (the H1 is
     the guide name, which every chunk already has).
   - Clean the prose before chunking: drop the "DO NOT READ THIS FILE ON GITHUB" banner, the
     `NOTE:` / `TIP:` / `INFO:` / `WARNING:` / `CAUTION:` / `IMPORTANT:` prefixes, reference-link
     definitions (`[foo]: https://...`, even when the URL wraps), horizontal rules, `<br>` and
     `**`. Links become their text: `[text](url)` and `[text][]` → `text`. Headings get the same
     link cleanup. Code inside fences is left untouched. (The Guides have no `{#anchor}` markers,
     so there is nothing to strip there.)
   - Pack paragraphs (split on blank lines) into chunks up to the word limit.
   - Cut any single paragraph longer than the limit by words.
4. **Save.** Each chunk is a row in `chunks` with `variant` (`w150`), `guide`, `position`,
   `heading` and `body`. Rows are found by `variant + guide + position` (a unique index), so
   re-running updates rows instead of duplicating them.
5. **Embed** (`EmbedChunkJob`, run with `perform_now`). The text to embed is
   `guide name > heading`, a newline, then the body. It is hashed with the model name (SHA256). If
   the hash matches the stored `content_hash`, the row is skipped. Otherwise `Embedder.call`
   returns the vector, and the job saves `embedding`, `content_hash` and `embedding_model`.
6. **Clean up.** If a guide now produces fewer chunks than before, its leftover rows are deleted.
7. **Second variant.** `bin/rails 'guides:ingest[30]'` stores 30-word chunks as `w30` in the same
   table. The page reads `w150`; the eval's "break it" run reads `w30` (`CHUNK_VARIANT=w30`).
8. **Re-running is safe and cheap.** The task prints how many chunks it embedded and how many were
   unchanged. A re-run with no changes embeds 0.
9. **The test database needs its own copy.** Run `RAILS_ENV=test bin/rails 'guides:ingest[150]'`
   (and `[30]`) before `bin/rails test test/evals`.

Measured on an M-series Mac: the first `w150` run embedded 4,705 chunks in 79 s, and the first
`w30` run embedded 17,828 in 253 s. After the chunker cleanup the tables hold 4,743 and 17,759
chunks.

## The embedding model

[`sentence-transformers/all-MiniLM-L6-v2`](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2),
run locally by the [informers](https://github.com/ankane/informers) gem and wrapped in
`app/services/embedder.rb`.

- **What it is.** An embedding model, not a chat model. It turns a sentence or short paragraph
  into a 384-dimensional vector, and texts with similar meaning get vectors that are close
  together. It was fine-tuned from MiniLM with a contrastive objective on over a billion sentence
  pairs. It's small (22.7M parameters), English-only and Apache-2.0.
- **Its limit.** It was trained on inputs of up to 256 tokens, and the model card says longer text
  is truncated at 256. informers actually cuts at 512 tokens (the tokenizer's `model_max_length`),
  so text between 256 and 512 tokens is still embedded, but past what the model learned from.
  Either way, long text is cut silently, which is why chunk size matters. At 150 words the median
  chunk is about 161 tokens.
- **Vectors.** One string in, one array of 384 floats out, mean-pooled and normalized (informers'
  defaults), compared by cosine distance.
- **Where it's used.** Twice, always the same model: once per chunk at ingestion, and once per
  question at search time. Vectors from different models aren't comparable.
- **Why this one:**
  1. Fully local. No API key, no cost, and no network after the first download
     (`bin/rails guides:warmup`), so the demo works offline.
  2. Small and fast enough to embed all the Guides on a laptop CPU and each question instantly.
  3. Built for short-passage semantic search, which matches our chunk sizes.
  4. A widely used, recognizable baseline.
  5. Its short input limit makes the chunking lesson concrete.
- **Trade-off.** Hosted embedding models (OpenAI, Bedrock, Cohere) are generally more accurate
  and accept much longer input, at the cost of an API key, money and a network call per question.
  To switch, change `Embedder::MODEL` and `DIMENSIONS`, update the vector size in the migration,
  and re-run ingestion. The model name is part of the content hash, so every row re-embeds
  automatically.

## The eval

```bash
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rails 'guides:ingest[150]'
RAILS_ENV=test bin/rails 'guides:ingest[30]'

bin/rails test test/evals                     # passes
CHUNK_VARIANT=w30 bin/rails test test/evals   # fails, on purpose
```

| Variant | Keyword | Vector | Hybrid | In-scope answered |
|---|---|---|---|---|
| `w150` | 62% | **100%** | **100%** | 100% |
| `w30` | 38% | 92% ❌ | 92% ❌ | 100% |

The floors are 95%, so one miss out of 13 questions fails the run. Grow `golden_set.yml` before
you trust smaller differences.

## Tuning

| Knob | Default | Notes |
|---|---|---|
| `MAX_DISTANCE` | `0.68` | In-scope questions score 0.23–0.64, unrelated ones 0.70+ |
| `CHUNK_VARIANT` | `w150` | Which chunk size the page and the eval read |
| `guides:ingest[N]` | `150` | Max words per chunk; median chunk is ~161 tokens |
| Eval floors | `0.95` | In `retrieval_eval_test.rb`, just below the `w150` baseline |

## Design notes

- **No vector index.** An exact scan over a few thousand rows takes milliseconds and is always
  right. HNSW plus `WHERE variant = ...` can return fewer rows than asked for.
- **One model for documents and questions.** The model name is part of the content hash, so
  changing models re-embeds everything.
- **No LLM answer.** Results are cited passages; generation is the next step.
- **A cutoff catches unrelated questions, not near-misses.** `configure Phoenix LiveView in Rails`
  scores 0.48 and gets answered from the Configuring guide.

<details>
<summary><strong>Build notes</strong>: what changed from the original spec</summary>

Built with Rails 8.1.3, Ruby 3.4.8, PostgreSQL 18.6, pgvector 0.8.7, neighbor 1.2.0 and
informers 1.3.0.

- **Truncation is 512 tokens, not 256.** informers uses the tokenizer's `model_max_length`, and
  MiniLM was trained on up to 256. At 150 words, 23% of chunks exceed 256 tokens and 36 exceed
  512.
- **Embeddings are normalized.** `Informers.pipeline("embedding", ...)` returns one flat array
  for a single string, mean-pooled and normalized.
- **The Guides use setext headings** (`Title` over `===` / `---`) for H1/H2. The chunker handles
  them and strips the GitHub banner, `NOTE:`/`TIP:` prefixes, link URLs and 637 reference-link
  definitions. Code in fences is kept.
- **The Phoenix question was replaced.** No cutoff rejects it without also rejecting real
  questions, and `multi-qa-MiniLM` gave the same result. `best hiking trails in Patagonia` took
  its place in the golden set.
- **30-word chunks only barely fail.** Every chunk carries `guide > heading`, so even short chunks
  usually find the right guide. The difference is easier to see on the page.
- **Known limits.** Release notes are indexed and sometimes rank high; drop them with
  `Chunk.where("guide LIKE '%release_notes'").delete_all`. A code block with blank lines can be
  split across two chunks.

</details>

## Credits

Content from the [Ruby on Rails Guides](https://guides.rubyonrails.org), published by the Rails
team under an attribution license. Every result links back to its guide.
