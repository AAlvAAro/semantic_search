# One page, one query, keyword and vector search side by side.
# The page always reads Chunk.current_variant (w150 unless CHUNK_VARIANT says
# otherwise); the w30 variant is only for the eval's "break it" run.
class SearchController < ApplicationController
  RESULTS = 5

  def index
    @query   = params[:q].to_s.strip
    @variant = Chunk.current_variant
    @indexed = Chunk.where(variant: @variant).where.not(embedding: nil).exists?
    return if @query.blank? || !@indexed

    @keyword = Chunk.keyword_search(@query, limit: RESULTS).to_a
    @vector  = Chunk.vector_search(@query, limit: RESULTS).to_a

    # The closest passage, and whether it is close enough to count as an answer.
    @best    = @vector.first
    @covered = @best.present? && @best.neighbor_distance <= ChunkSearch::MAX_DISTANCE
  end
end
