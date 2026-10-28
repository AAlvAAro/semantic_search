# Demo runbook: Semantic Search in Rails

Exact steps for the live part of the talk. The queries below were picked in rehearsal against
the Rails Guides on `main` (October 2026); re-check them if you re-clone the Guides.

## The day before

- [ ] `bin/rails guides:warmup` (model is cached, so no network needed on stage)
- [ ] Both variants ingested in development AND test: `guides:ingest[150]` and `guides:ingest[30]`
- [ ] `MAX_DISTANCE` calibrated from real distances (see README, Tuning)
- [ ] `bin/rails test test/evals` passes, and `CHUNK_VARIANT=w30 bin/rails test test/evals` fails
- [ ] Turn Wi-Fi off and run every step below once. If anything needs the network, fix it now.
      `INFORMERS_OFFLINE=1 bin/rails server` makes informers refuse any download, as a belt and braces.
- [ ] Record a 60-second screen capture of the whole sequence as a fallback

## Screen setup

- Browser at 125 to 150% zoom, one tab on http://localhost:3000
- Terminal with large font, already in the project directory, with the two eval commands in
  history (up arrow, enter)
- Notifications off

## Live sequence (about 5 minutes)

The page shows two boxes for the same question: **Keyword search** on the left, **Vector search** on
the right. The vector box carries the verdict and the distance ruler at the top, and dims any result
past the cutoff.

### 1. Hook: meaning beats keywords (1.5 min)

Ask:

`make sure a field is not left blank before saving`

Keyword box: "No passage contains every word of this question." Vector box: the verdict is
**Active Record Validations > Validations > presence** (distance 0.49), and the other results are
`absence`, Skipping Validations and `:allow_blank`.

Backup: `do something once a record is saved for good`. Keyword is empty, and vector shows
**Active Record Callbacks > Creating an Object** (0.55, it lists `after_commit`), with the
`after_commit` and `after_rollback` section third.

Say: "Keyword search needs every word to appear. Nobody asks questions in the Guides' own words."

Careful with ad-lib questions: Postgres drops stopwords and stems the rest, so a question made of
everyday Rails words still matches. `how to save a record after running some changes` becomes
`save & record & run & chang`, and 10 passages contain all four.

### 2. Exact names: keyword earns its place (1 min)

Ask `after_commit`. Now keyword has five results, including **Active Record Callbacks > Transaction
Callbacks > Aliases for after_commit** (its top hit is a release note that mentions the term).
Vector finds the same section, at distances around 0.43.

Say: "When you know the exact name, keyword search is great. Real apps run both."

### 3. Out of scope (1.5 min)

Ask `best hiking trails in Patagonia`.
Keyword is empty. The vector box reads "Not covered in the Guides", with the dot (0.73) past the
red cutoff line (0.68), and all five results are dimmed and labelled "past cutoff".

Say: "Vector search always returns something. The cutoff decides what counts."

Do not use `how do I configure Phoenix LiveView in Rails` for this step. It scores 0.48, sits next
to the Configuring guide, and is answered with a normal verdict. If someone asks, that is the
point: "A distance cutoff catches unrelated questions, not plausible-sounding wrong ones."

### 4. Measure it (1 min)

In the terminal:

```bash
bin/rails test test/evals
CHUNK_VARIANT=w30 bin/rails test test/evals
```

The first passes and prints hit rates (keyword 62%, vector 100%, hybrid 100%). The second runs the
same questions against 30-word chunks and fails: vector and hybrid drop to 92%, missing
`use different settings in production and development`.

Say: "Same model, same questions, I only changed how I cut the text, and the test caught it.
Chunk size, model or cutoff changes are a test result, not a feeling."

## If something breaks

- **Page error or slow first query:** the model is loading. Run `bin/rails guides:warmup` and retry.
- **"No passages for variant w150 yet":** run `bin/rails 'guides:ingest[150]'` (about 80 seconds) and switch to the recorded clip meanwhile.
- **Eval results differ from rehearsal:** show the recorded run and move on. The point is the shape, not the exact numbers.
- **Anything else:** play the recording and narrate over it.
