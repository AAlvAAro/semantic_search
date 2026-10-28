class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :chunks do |t|
      t.string  :variant,  null: false              # "w150" = chunks of at most 150 words
      t.string  :guide,    null: false              # guide file name without .md
      t.integer :position, null: false              # order of the chunk inside its guide
      t.string  :heading,  null: false, default: "" # "Callbacks > Transaction Callbacks"
      t.text    :body,     null: false
      t.vector  :embedding, limit: 384              # all-MiniLM-L6-v2
      t.string  :content_hash                       # SHA256 of model name + embedded text
      t.string  :embedding_model
      t.timestamps
    end

    add_index :chunks, [ :variant, :guide, :position ], unique: true

    # No vector index on purpose. See the comment at the top of ChunkSearch.
  end
end
