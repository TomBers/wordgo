defmodule Wordgo.Test.EmbeddingsHelper do
  @moduledoc """
  Test helper module that patches the real embeddings service with a mock
  implementation for testing purposes.
  """

  alias Wordgo.Test.Mocks.WordEmbeddingsMock

  @doc """
  Setup function for tests that require word embeddings.
  This patches the real implementation with a mock for testing.

  Usage:

  setup :setup_mock_embeddings
  """
  def setup_mock_embeddings(_context) do
    # Store original module functions to restore after test
    original_module = Wordgo.WordToVec.Embeddings
    _original_serving_fn = &original_module.serving/0

    # Mock the serving function
    mock_fn = fn -> WordEmbeddingsMock.serving() end

    # Replace the real function with our mock
    :meck.new(Wordgo.WordToVec.Embeddings, [:passthrough])
    :meck.expect(Wordgo.WordToVec.Embeddings, :serving, mock_fn)

    # Return a function to clean up after the test
    on_exit = fn ->
      :meck.unload(Wordgo.WordToVec.Embeddings)
    end

    %{on_exit: on_exit}
  end
end
