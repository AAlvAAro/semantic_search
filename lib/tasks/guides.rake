namespace :guides do
  desc "Download and load the embedding model once (needs internet the first time)"
  task warmup: :environment do
    started = Time.current
    vector  = Embedder.call("warm up")
    puts "#{Embedder::MODEL} ready: #{vector.size} dimensions in #{(Time.current - started).round(1)}s"
  end

  desc "Chunk and embed the Rails Guides. Usage: bin/rails 'guides:ingest[150]' (max words per chunk)"
  task :ingest, [ :words ] => :environment do |_task, args|
    words   = Integer(args[:words] || 150)
    variant = "w#{words}"
    path    = Pathname(ENV.fetch("GUIDES_PATH", Rails.root.join("vendor/rails/guides/source").to_s))
    chunker = GuideChunker.new(max_words: words)

    files = Dir[path.join("*.md")].sort
    abort "No markdown files in #{path}. Clone rails/rails into vendor/rails or set GUIDES_PATH." if files.empty?

    total    = 0
    embedded = 0
    started  = Time.current
    files.each do |file|
      guide_started = Time.current
      pieces = chunker.call(file)
      guide  = File.basename(file, ".md")

      pieces.each_with_index do |piece, position|
        chunk = Chunk.find_or_initialize_by(variant: variant, guide: guide, position: position)
        chunk.update!(heading: piece.heading, body: piece.body)

        # perform_now keeps the rake task simple and the progress visible.
        # In a real app you would use perform_later.
        embedded += 1 if EmbedChunkJob.perform_now(chunk.id)
      end

      # Drop leftovers if this guide now produces fewer chunks than before.
      Chunk.where(variant: variant, guide: guide).where("position >= ?", pieces.size).delete_all

      total += pieces.size
      puts "#{guide}: #{pieces.size} chunks in #{(Time.current - guide_started).round(1)}s"
    end

    puts "Done: #{total} chunks in variant #{variant}, #{embedded} embedded, " \
         "#{total - embedded} unchanged, in #{(Time.current - started).round}s"
  end
end
