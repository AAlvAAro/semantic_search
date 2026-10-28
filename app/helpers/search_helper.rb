module SearchHelper
  # A readable excerpt: fenced code collapsed to [code], markdown symbols removed.
  # Underscores stay, so method names like after_commit survive.
  def excerpt_for(chunk, length: 240)
    text = chunk.body
                .gsub(/```.*?```/m, " [code] ")
                .gsub(/[#*`>]+/, " ")
                .squish
    truncate(text, length: length, separator: " ")
  end

  def distance_label(distance)
    number_with_precision(distance, precision: 2)
  end

  # Position on the ruler, 0 = same meaning, 1 = unrelated. Cosine distance can
  # go above 1, so clamp it to keep the dot on the track.
  def ruler_position(distance)
    distance.to_f.clamp(0.0, 1.0)
  end
end
