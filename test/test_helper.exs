# Setup mocks for embeddings in tests
Code.require_file("test/support/mocks/word_embeddings_mock.ex")

# Define a module attribute to track if we've already mocked embeddings
Application.put_env(:wordgo, :embeddings_mocked, false)

# Patch the embeddings service for tests
unless Application.get_env(:wordgo, :embeddings_mocked) do
  # Replace the real Embeddings.serving function with our mock
  :meck.new(Wordgo.WordToVec.Embeddings, [:passthrough])

  :meck.expect(Wordgo.WordToVec.Embeddings, :serving, fn ->
    Wordgo.Test.Mocks.WordEmbeddingsMock.serving()
  end)

  # Mark as mocked so we don't do it twice
  Application.put_env(:wordgo, :embeddings_mocked, true)
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Wordgo.Repo, :manual)
