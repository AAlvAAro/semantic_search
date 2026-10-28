# Splits one Rails Guide (markdown) into chunks:
#   1. split at headings, keeping the heading path ("Callbacks > Transaction Callbacks")
#   2. inside a section, pack paragraphs until the word cap is reached
#   3. a single paragraph longer than the cap is cut by words
#
# The cap matters: all-MiniLM-L6-v2 was trained on up to 256 tokens and
# informers drops everything past 512. Chunks that are too long get blurry or
# lose their tail; chunks that are too short lose their context. That tradeoff
# is the live "break it" moment of the talk.
class GuideChunker
  Piece = Struct.new(:guide, :heading, :body, keyword_init: true)

  DEFAULT_WORDS = Integer(ENV.fetch("CHUNK_WORDS", "150"))

  # The Guides write H1 and H2 as setext ("Title" over a line of = or -) and
  # H3 and below as ATX ("### Title").
  ATX_HEADING = /\A(\#{1,6})\s+(.+?)\s*\z/
  UNDERLINE   = /\A(=+|-+)\s*\z/

  # Markup that only adds noise to an embedding. Code inside fences is kept.
  NOISE = [
    [ /^\*\*DO NOT READ THIS FILE ON GITHUB.*$/, "" ], # banner at the top of every guide
    [ /^\[[^\]\n]+\]:\s+\S+[ \t]*$/, "" ],              # link reference definitions, URL may wrap
    [ /^-{3,}[ \t]*$/, "" ],                           # horizontal rule after the intro
    [ /^(NOTE|TIP|INFO|WARNING|CAUTION|IMPORTANT)[:.][ \t]*/, "" ],
    [ /\[([^\]]+)\]\([^)]*\)/, '\1' ],                 # [text](url), also across lines -> text
    [ /\[([^\]]+)\]\[[^\]]*\]/, '\1' ],                # [text][] and [text][ref] -> text
    [ /<br\s*\/?>/, " " ],
    [ /\*\*/, "" ]
  ].freeze

  def initialize(max_words: DEFAULT_WORDS)
    @max_words = max_words
  end

  def call(path)
    guide = File.basename(path, ".md")

    split_sections(File.read(path)).flat_map do |heading, text|
      window(text).map { |body| Piece.new(guide: guide, heading: heading, body: body) }
    end
  end

  private

  # Returns [[heading_path, text], ...]. Headings inside fenced code blocks
  # (a "# comment" in a Ruby snippet) are not headings. The H1 is the guide
  # title, which the chunk already carries as `guide`, so paths start at H2.
  def split_sections(markdown)
    sections = []
    stack    = []
    current  = { heading: "", lines: [] }
    in_fence = false
    lines    = markdown.lines.map(&:chomp)

    lines.each_with_index do |line, index|
      next if line == :underline

      if line.lstrip.start_with?("```")
        in_fence = !in_fence
        current[:lines] << line
        next
      end

      underline = lines[index + 1]
      level, title =
        if in_fence
          nil
        elsif (match = ATX_HEADING.match(line))
          [ match[1].size, clean(match[2]) ]
        elsif line.strip.present? && underline.is_a?(String) && (match = UNDERLINE.match(underline))
          lines[index + 1] = :underline
          [ match[1].start_with?("=") ? 1 : 2, clean(line) ]
        end

      if level
        sections << current
        stack   = level == 1 ? [] : stack.first(level - 2) << title
        current = { heading: stack.join(" > "), lines: [] }
      else
        current[:lines] << line
      end
    end
    sections << current

    sections
      .map { |section| [ section[:heading], clean(section[:lines].join("\n")) ] }
      .reject { |_heading, text| text.empty? }
  end

  # Cleans prose only; fenced code passes through untouched.
  def clean(text)
    text.split(/(^[ \t]*```.*?^[ \t]*```[^\n]*$)/m).map.with_index { |part, index|
      index.odd? ? part : NOISE.reduce(part) { |prose, (pattern, replacement)| prose.gsub(pattern, replacement) }
    }.join.gsub(/\n{3,}/, "\n\n").strip
  end

  def window(text)
    windows = []
    buffer  = []
    count   = 0

    text.split(/\n{2,}/).each do |paragraph|
      words = paragraph.split.size
      if count + words > @max_words && buffer.any?
        windows << buffer.join("\n\n")
        buffer = []
        count  = 0
      end
      buffer << paragraph
      count  += words
    end
    windows << buffer.join("\n\n") if buffer.any?

    windows.flat_map { |chunk| hard_split(chunk) }
  end

  def hard_split(text)
    words = text.split
    return [ text ] if words.size <= @max_words

    words.each_slice(@max_words).map { |slice| slice.join(" ") }
  end
end
