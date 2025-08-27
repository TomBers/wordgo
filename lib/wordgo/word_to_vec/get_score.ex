defmodule Wordgo.WordToVec.GetScore do
  def run do
    run("Bob", "Bill")
  end

  def run(word1, word2) do
    url = "http://localhost:8000"
    path = "/similarity/#{word1}/#{word2}"
    Req.get!(url <> path).body["similarity"]
  end
end
