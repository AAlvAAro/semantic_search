# One passage of one Rails Guide, under one chunking variant ("w150" means
# chunks of at most 150 words). Keeping variants side by side in one table lets
# the demo switch chunk sizes instantly instead of re-embedding live.
class Chunk < ApplicationRecord
  include ChunkSearch

  has_neighbors :embedding

  # What actually gets embedded: guide and heading context plus the passage.
  # Changing this text changes content_hash, so the job re-embeds the row.
  def embedding_text
    "#{guide.tr('_', ' ')} > #{heading}\n#{body}"
  end

  def citation
    [ guide.tr("_", " ").titleize, heading.delete("`").presence ].compact.join(" > ")
  end

  def url
    "https://guides.rubyonrails.org/#{guide}.html"
  end
end
