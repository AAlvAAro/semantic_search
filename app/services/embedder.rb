# Local embeddings via the informers gem (ONNX Runtime). No AWS, no API keys.
# The model downloads once into the local Hugging Face cache on first use, so
# run `Embedder.call("warm up")` before the talk while you still have internet.
#
# all-MiniLM-L6-v2 returns 384-dimension vectors. It was trained on inputs of
# up to 256 tokens; informers cuts input at 512 (model_max_length in the
# tokenizer config), so text between the two is embedded but past what the
# model learned from. If you change the model, change DIMENSIONS and the
# migration's vector size too, and re-embed everything (the content hash
# includes MODEL).
class Embedder
  MODEL      = "sentence-transformers/all-MiniLM-L6-v2"
  DIMENSIONS = 384

  # One string in, one Array<Float> out, mean-pooled and normalized to length 1
  # (informers' defaults for the "embedding" pipeline).
  def self.call(text)
    pipeline.call(text)
  end

  def self.pipeline
    @pipeline ||= Informers.pipeline("embedding", MODEL)
  end
end
