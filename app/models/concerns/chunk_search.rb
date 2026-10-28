# Four ways to query the same chunks, so the talk can compare them:
#
#   Chunk.keyword_search("run code after commit")   # Postgres full-text search
#   Chunk.vector_search("run code after commit")    # pgvector, always returns something
#   Chunk.hybrid_search("run code after commit")    # both, merged with RRF
#   Chunk.semantic_search("how do I center a div")  # vector + a distance cutoff => can say "no"
#
# There is deliberately NO approximate (HNSW) index on the embedding column.
# At a few thousand chunks an exact scan takes milliseconds and is always
# correct. An HNSW index plus a WHERE on `variant` can also return fewer rows
# than requested, because the filter is applied after the index scan.
# Add the index when the table outgrows exact search.
module ChunkSearch
  extend ActiveSupport::Concern

  # Reciprocal Rank Fusion constant (60 is the value from the original paper).
  RRF_K = 60

  # Cosine distance above which a match counts as "not in the Guides".
  # Calibrated on the golden set (best match, all-MiniLM-L6-v2):
  #   in-scope questions     0.37 to 0.64 (w150), 0.23 to 0.53 (w30)
  #   unrelated questions    0.70 to 0.83 (sourdough, PyTorch, Patagonia, ...)
  # It does NOT catch near-misses: "configure Phoenix LiveView in Rails" scores
  # 0.48 because it sits next to the Configuring guide. A distance cutoff
  # rejects unrelated questions, not plausible-sounding wrong ones.
  MAX_DISTANCE = Float(ENV.fetch("MAX_DISTANCE", "0.68"))

  class_methods do
    def current_variant
      ENV.fetch("CHUNK_VARIANT", "w150")
    end

    # plainto_tsquery ANDs every term, so a natural-language question only
    # matches if ALL its stems appear in one chunk. That strictness is what the
    # keyword column of the demo should show.
    def keyword_search(query, limit: 10, variant: current_variant)
      document = "to_tsvector('english', coalesce(guide, '') || ' ' || coalesce(heading, '') || ' ' || coalesce(body, ''))"
      tsquery  = sanitize_sql_array([ "plainto_tsquery('english', ?)", query ])

      where(variant: variant)
        .where("#{document} @@ #{tsquery}")
        .order(Arel.sql("ts_rank(#{document}, #{tsquery}) DESC"))
        .limit(limit)
    end

    # Nearest neighbors by cosine distance. Every row gets a neighbor_distance.
    # Query and documents must be embedded with the same model.
    def vector_search(query, limit: 10, variant: current_variant)
      where(variant: variant)
        .nearest_neighbors(:embedding, Embedder.call(query), distance: "cosine")
        .limit(limit)
    end

    # Vector search that is allowed to answer "nothing relevant". Without the
    # cutoff, vector search returns the closest chunks even for nonsense.
    def semantic_search(query, limit: 5, max_distance: MAX_DISTANCE, variant: current_variant)
      vector_search(query, limit: limit, variant: variant)
        .select { |chunk| chunk.neighbor_distance <= max_distance }
    end

    # Merge keyword and vector rankings with Reciprocal Rank Fusion: each chunk
    # scores 1 / (k + rank) in every list it appears in, and the scores add up.
    def hybrid_search(query, limit: 10, pool: 50, variant: current_variant)
      lists = [
        keyword_search(query, limit: pool, variant: variant).to_a,
        vector_search(query, limit: pool, variant: variant).to_a
      ]

      scores = Hash.new(0.0)
      lists.each do |list|
        list.each_with_index { |chunk, index| scores[chunk.id] += 1.0 / (RRF_K + index + 1) }
      end

      by_id = lists.flatten.index_by(&:id)
      scores.sort_by { |_id, score| -score }.first(limit).map { |id, _score| by_id[id] }
    end
  end
end
