# Embeds one chunk. Safe to run any number of times: the stored content_hash
# covers the model name and the exact text that was embedded, so unchanged rows
# are skipped and a changed text or a changed model re-embeds automatically.
# Returns true when it called the model, so the ingest task can count calls.
class EmbedChunkJob < ApplicationJob
  queue_as :default

  def perform(chunk_id)
    chunk  = Chunk.find(chunk_id)
    text   = chunk.embedding_text
    digest = Digest::SHA256.hexdigest("#{Embedder::MODEL}:#{text}")
    return false if chunk.content_hash == digest

    chunk.update!(
      embedding: Embedder.call(text),
      content_hash: digest,
      embedding_model: Embedder::MODEL
    )
    true
  end
end
