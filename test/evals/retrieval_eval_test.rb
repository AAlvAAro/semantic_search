require "test_helper"

# Retrieval eval. Two questions, both about RETRIEVAL (not generated answers):
#
#   1. For questions the Guides cover: does the top K contain a chunk from an
#      acceptable guide? (hit rate@K, per strategy)
#   2. For questions the Guides cannot answer: does semantic_search return
#      nothing, while still answering the in-scope questions?
#
# Runs against a database that already holds embedded chunks, so populate the
# test DB once before running it:
#   RAILS_ENV=test bin/rails 'guides:ingest[150]'
#   RAILS_ENV=test bin/rails 'guides:ingest[30]'      # for the live "break it" demo
# then:
#   bin/rails test test/evals
#   CHUNK_VARIANT=w30 bin/rails test test/evals      # should fail: chunks too small
class RetrievalEvalTest < ActiveSupport::TestCase
  K = 5

  # Floors sit just below the w150 baseline (vector 100%, hybrid 100%,
  # keyword 62%, answerable 100%). With 13 questions one miss costs 8 points,
  # so 0.95 means "no misses": w30 misses one question (92%) and fails.
  # Grow the golden set before trusting smaller differences.
  MIN_HIT_RATE        = { vector: 0.95, hybrid: 0.95 }.freeze
  MIN_ANSWERABLE_RATE = 0.9

  GOLDEN       = YAML.load_file(Rails.root.join("test/evals/golden_set.yml")).freeze
  IN_SCOPE     = GOLDEN.fetch("in_scope").freeze
  OUT_OF_SCOPE = GOLDEN.fetch("out_of_scope").freeze

  STRATEGIES = {
    keyword: ->(query) { Chunk.keyword_search(query, limit: K) },
    vector:  ->(query) { Chunk.vector_search(query, limit: K) },
    hybrid:  ->(query) { Chunk.hybrid_search(query, limit: K) }
  }.freeze

  test "data exists for the variant under test" do
    assert Chunk.where(variant: Chunk.current_variant).exists?,
           "No chunks for variant #{Chunk.current_variant}. Run the ingest task first."
  end

  test "every in-scope question has at least one acceptable guide in the data" do
    IN_SCOPE.each do |item|
      assert Chunk.where(variant: Chunk.current_variant, guide: item["expected"]).exists?,
             "None of #{item['expected'].inspect} found in the data for: #{item['question']}"
    end
  end

  test "retrieval hit rate at K stays above the floor" do
    results = STRATEGIES.transform_values { |search| evaluate(search) }
    print_hit_rates(results)

    MIN_HIT_RATE.each do |strategy, floor|
      rate   = results[strategy][:rate]
      missed = results[strategy][:missed]
      assert_operator rate, :>=, floor,
                      "#{strategy} hit rate@#{K} was #{(rate * 100).round}%, floor is #{(floor * 100).round}% " \
                      "(variant #{Chunk.current_variant}). Missed: #{missed.join(' | ')}"
    end
  end

  test "out-of-scope questions are rejected and in-scope questions are not" do
    answered = IN_SCOPE.count { |item| Chunk.semantic_search(item["question"]).any? }
    rate     = answered.to_f / IN_SCOPE.size
    puts format("\nAnswerable in-scope questions: %d%%", (rate * 100).round)

    assert_operator rate, :>=, MIN_ANSWERABLE_RATE,
                    "Cutoff #{ChunkSearch::MAX_DISTANCE} rejects too many in-scope questions"

    OUT_OF_SCOPE.each do |question|
      assert_empty Chunk.semantic_search(question),
                   "Expected 'not in the Guides' but got an answer for: #{question}"
    end
  end

  private

  def evaluate(search)
    missed = IN_SCOPE.reject { |item| hit?(search.call(item["question"]), item["expected"]) }
                     .map { |item| item["question"] }
    { rate: 1.0 - (missed.size.to_f / IN_SCOPE.size), missed: missed }
  end

  def hit?(chunks, expected_guides)
    chunks.any? { |chunk| expected_guides.include?(chunk.guide) }
  end

  def print_hit_rates(results)
    puts "\nHit rate@#{K} over #{IN_SCOPE.size} questions (variant #{Chunk.current_variant})"
    results.each { |strategy, result| puts format("  %-8s %3d%%", strategy, (result[:rate] * 100).round) }
  end
end
