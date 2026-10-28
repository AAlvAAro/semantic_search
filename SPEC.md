# Semantic Search in Rails

A small, fully local Rails app for a 20-minute internal tech talk. It searches the Rails Guides by meaning,
compares keyword vs vector vs hybrid search on the same data, can say "Not covered in the Guides", and ships a
retrieval eval as a Minitest test. Simple on purpose: quick to build, quick to explain.

## Talk moments the app must support

1. **Hook:** a natural-language question where keyword search finds nothing and vector search finds the right guide.
2. **Break it live:** switch chunk size from 150 words to 30 words (`?variant=w30`) and watch results get worse.
3. **Out of scope:** an unrelated question ("how do I configure Phoenix LiveView in Rails") shows "Not covered in the
   Guides" instead of confident nonsense.
4. **Measure it:** `bin/rails test test/evals` prints hit rate@5 per strategy and fails when quality drops.

`docs/DEMO.md` has the exact live sequence. The app must make every step of it work.

## App scaffold

- Plain `rails new`, no boilerplate, starter kit or template. The audience is Rails developers and should
  recognize every file.
- Generate with PostgreSQL and skip what the demo doesn't use. Check `rails new --help` for the exact flags in the
  current Rails version, roughly:
  `rails new semantic_search --database=postgresql --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-jbuilder`
- Keep the Rails defaults for everything else (Propshaft, importmap, Turbo, ERB, Minitest).
- No CSS framework and no CDN. `app/assets/stylesheets/search.css` is the whole stylesheet and uses system fonts,
  so the page works offline. Make sure the layout links it.
- Projector rules: light background, large type, clear columns, and a visually distinct "Not covered in the Guides"
  state. Keep the existing design; don't add components or decoration.

## Reference files already in this repo

These are the reference design. Treat them as the source of truth for behavior, but they have NOT been run.
Wire them in, fix whatever breaks, and tell me what you changed. Copy them over the generated files where paths
collide (`config/routes.rb`).

- `app/services/guide_chunker.rb`: splits a guide by heading, caps chunk size in words
- `app/services/embedder.rb`: local embeddings via the `informers` gem (all-MiniLM-L6-v2, 384 dimensions)
- `app/models/chunk.rb` and `app/models/concerns/chunk_search.rb`: model plus keyword, vector, hybrid (RRF) and
  `semantic_search` (vector + distance cutoff)
- `app/jobs/embed_chunk_job.rb`: idempotent embedding job (content hash includes the model name)
- `db/migrate/20261026120000_create_chunks.rb`: the `chunks` table (adjust the migration version to the app's Rails)
- `lib/tasks/guides.rake`: `guides:warmup` and `bin/rails 'guides:ingest[150]'`
- `app/controllers/search_controller.rb`, `app/helpers/search_helper.rb`, `app/views/search/*`,
  `app/assets/stylesheets/search.css`, `config/routes.rb`: the single search page
- `test/evals/retrieval_eval_test.rb` and `test/evals/golden_set.yml`: the eval
- `README.md` and `docs/DEMO.md`: keep them accurate as you build. Update, don't rewrite.

## Stack and decisions (already made)

- Rails (current stable), PostgreSQL with the `pgvector` extension, `neighbor` gem for `has_neighbors`
- Everything runs locally. No AWS, no API keys, no network after the one-time model download.
- Embeddings: the `informers` gem with `sentence-transformers/all-MiniLM-L6-v2`. Input is truncated at 256 tokens, so
  keep `embedding_text` under that (code-heavy chunks have more tokens per word; lower the word cap if you see
  truncation).
- Model is `Chunk` with a `variant` column ("w150", "w30") so several chunk sizes live in one table and the demo can
  switch instantly. Unique on `[variant, guide, position]`.
- **No HNSW or IVFFlat index.** At a few thousand chunks an exact scan is fast and always correct, and an approximate
  index plus a `WHERE variant = ...` filter can return fewer rows than requested. Keep the explanation in the code
  comment; it is also a slide.
- No LLM answer generation. Results are cited passages (guide > heading, linked to guides.rubyonrails.org).

## Data

- Source: a shallow clone of rails/rails into `vendor/rails` (add it to `.gitignore`), reading `guides/source/*.md`.
  Command: `git clone --depth 1 https://github.com/rails/rails vendor/rails`
- Do NOT assume the markdown layout. Open several real guide files first and check how headings, anchors, fenced
  code and markers like `NOTE:` / `TIP:` / `INFO:` are written. Adjust `GuideChunker` and strip markup that would
  pollute embeddings. Report what you found.
- `test/evals/golden_set.yml` uses my best guess at guide file names. Verify them against `guides/source` and fix.

## Build steps (in this order, run tests after each)

1. `rails new` as described in App scaffold; add gems `neighbor` and `informers`.
2. Add the migration and model; `bin/rails db:prepare`.
3. Wire in the services and job; `bin/rails guides:warmup` returns 384 dimensions.
4. Run `bin/rails 'guides:ingest[150]'`, then `bin/rails 'guides:ingest[30]'`. Log chunk counts and timing.
5. Wire in the search page (controller, helper, views, CSS, routes). Check it at a projector-like 1280x720 window.
6. Calibrate `MAX_DISTANCE`: print `neighbor_distance` for the golden in-scope and out-of-scope questions and choose a
   value between the two groups. Update the constant and its comment with the numbers you saw.
7. Run the eval. Set the floors in `retrieval_eval_test.rb` just below the baseline for variant `w150`, and confirm
   that `CHUNK_VARIANT=w30` fails.
8. Walk through `docs/DEMO.md`. Replace the candidate hook queries with the ones that work best, and note them.
9. Update `README.md` with anything that changed.

## Acceptance criteria

- `bin/rails test` passes; `bin/rails test test/evals` prints hit rate@5 for keyword, vector and hybrid
- Hook: a natural-language query where keyword returns nothing and vector returns a relevant guide
- Out of scope: the three `out_of_scope` golden questions show "Not covered in the Guides"
- `CHUNK_VARIANT=w30 bin/rails test test/evals` fails; `w150` passes
- Re-running `guides:ingest` makes no embedding calls for unchanged chunks
- The app works with the network disabled after the first model download

## Constraints

- Do not add gems or services beyond those listed without asking.
- Verify gem APIs and versions against current docs; don't assume. In particular check what `Informers.pipeline`
  returns for a single string and whether vectors are normalized by default.
- Out of scope: tenant filtering, streaming, agents, knowledge graph, LLM generation, any cloud service.
- If something in the reference files conflicts with what you find, prefer the docs and tell me.
