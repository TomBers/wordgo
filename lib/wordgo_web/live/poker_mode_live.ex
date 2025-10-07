defmodule WordgoWeb.PokerModeLive do
  use WordgoWeb, :live_view

  alias Wordgo.WordToVec.{GetScore, Vocabulary}

  @suggestions_count 18
  @suggestions_pool_size 300
  @ai_target_similarity 0.7

  # === Lifecycle ===

  @impl true
  def mount(params, _session, socket) do
    # params["ai"] in ["true", true, "1", 1, "on"]
    ai_enabled = true

    {base1, base2} = pick_base_words()

    manual_form =
      Phoenix.Component.to_form(
        %{"w1" => "", "w2" => "", "w3" => ""},
        as: :hand
      )

    socket =
      socket
      |> assign(:current_scope, "poker")
      |> assign(:ai_enabled, ai_enabled)
      |> assign(:base_words, [base1, base2])
      |> assign(:suggestions, [])
      |> assign(:selection, MapSet.new())
      # :select | :manual
      |> assign(:mode, :select)
      |> assign(:manual_form, manual_form)
      |> assign(:error_message, nil)
      |> assign(:round_over?, false)
      |> assign(:result, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    suggestions = build_suggestions(socket.assigns.base_words)
    {:noreply, assign(socket, :suggestions, suggestions)}
  end

  # === Events ===

  @impl true
  def handle_event("toggle_mode", _params, socket) do
    new_mode =
      case socket.assigns.mode do
        :select -> :manual
        :manual -> :select
        _ -> :select
      end

    {:noreply,
     socket
     |> assign(:mode, new_mode)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("toggle_select", %{"w" => word}, socket) do
    if socket.assigns.round_over? do
      {:noreply, socket}
    else
      sel = socket.assigns.selection

      sel =
        if MapSet.member?(sel, word) do
          MapSet.delete(sel, word)
        else
          # Max 3 selections
          if MapSet.size(sel) >= 3 do
            sel
          else
            MapSet.put(sel, word)
          end
        end

      {:noreply, assign(socket, selection: sel, error_message: nil)}
    end
  end

  @impl true
  def handle_event("change_hand", %{"hand" => params}, socket) do
    {:noreply, assign(socket, :manual_form, Phoenix.Component.to_form(params, as: :hand))}
  end

  @impl true
  def handle_event("submit_hand", _params, socket) do
    if socket.assigns.round_over? do
      {:noreply, socket}
    else
      case socket.assigns.mode do
        :select ->
          submit_from_selection(socket)

        :manual ->
          submit_from_manual(socket)
      end
    end
  end

  @impl true
  def handle_event("deal", _params, socket) do
    {base1, base2} = pick_base_words()
    suggestions = build_suggestions([base1, base2])

    {:noreply,
     socket
     |> assign(:base_words, [base1, base2])
     |> assign(:suggestions, suggestions)
     |> assign(:selection, MapSet.new())
     |> assign(:error_message, nil)
     |> assign(:round_over?, false)
     |> assign(:result, nil)
     |> assign(
       :manual_form,
       Phoenix.Component.to_form(%{"w1" => "", "w2" => "", "w3" => ""}, as: :hand)
     )}
  end

  @impl true
  def handle_event("regen_suggestions", _params, socket) do
    suggestions = build_suggestions(socket.assigns.base_words)

    {:noreply,
     socket
     |> assign(:suggestions, suggestions)
     |> assign(:selection, MapSet.new())
     |> assign(:error_message, nil)}
  end

  # === Rendering ===

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl px-4 py-6 space-y-6">
        <header class="space-y-1">
          <h1 class="text-2xl font-bold">Poker Mode</h1>
          <p class="text-sm text-gray-600 dark:text-gray-300">
            Two base words are dealt randomly. Pick or enter three words to make your best 5-word "hand". Highest average semantic similarity wins.
          </p>
        </header>

        <section class="grid gap-4 md:grid-cols-3">
          <div class="md:col-span-2 space-y-4">
            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-xs text-gray-500 dark:text-gray-400">Base words</p>
                  <div class="mt-1 flex flex-wrap gap-2">
                    <%= for w <- @base_words do %>
                      <span class="px-2 py-1 rounded bg-amber-100 dark:bg-amber-900/40 text-amber-900 dark:text-amber-100 text-sm">
                        {w}
                      </span>
                    <% end %>
                  </div>
                </div>
                <div class="text-right">
                  <.button phx-click="deal" class="btn btn-sm">Deal new</.button>
                </div>
              </div>
            </div>

            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800 space-y-3">
              <div class="flex items-center justify-between">
                <p class="font-medium">Your 3 words</p>
                <div class="flex items-center gap-2">
                  <span class="text-sm text-gray-600 dark:text-gray-300">
                    Mode:
                    <span class={[
                      "ml-1 px-2 py-0.5 rounded text-xs",
                      @mode == :select && "bg-blue-100 dark:bg-blue-900/40",
                      @mode == :manual && "bg-purple-100 dark:bg-purple-900/40"
                    ]}>
                      {(@mode == :select && "Select") || "Manual"}
                    </span>
                  </span>
                  <.button phx-click="toggle_mode" class="btn btn-sm">Toggle mode</.button>
                </div>
              </div>

              <%= if @error_message do %>
                <div class="px-3 py-2 rounded text-sm bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200 border border-red-300 dark:border-red-700">
                  {@error_message}
                </div>
              <% end %>

              <%= if @mode == :select do %>
                <div>
                  <div class="mb-2 flex items-center justify-between">
                    <p class="text-xs text-gray-600 dark:text-gray-400">
                      Select exactly three words
                    </p>
                    <div class="text-xs">
                      Selected:
                      <span class={[
                        "ml-1 px-1.5 py-0.5 rounded",
                        MapSet.size(@selection) == 3 && "bg-green-200 dark:bg-green-900/40",
                        MapSet.size(@selection) != 3 && "bg-gray-200 dark:bg-gray-700"
                      ]}>
                        {MapSet.size(@selection)} / 3
                      </span>
                    </div>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <%= for w <- @suggestions do %>
                      <% selected? = MapSet.member?(@selection, w) %>
                      <button
                        type="button"
                        phx-click="toggle_select"
                        phx-value-w={w}
                        class={[
                          "px-2 py-1 rounded border text-sm transition",
                          selected? &&
                            "bg-blue-600 border-blue-700 text-white hover:brightness-110",
                          !selected? &&
                            "bg-white dark:bg-gray-700 border-gray-300 dark:border-gray-600 text-gray-800 dark:text-gray-100 hover:brightness-95"
                        ]}
                        disabled={@round_over?}
                        aria-pressed={selected?}
                      >
                        {w}
                      </button>
                    <% end %>
                  </div>
                  <div class="mt-3">
                    <.button phx-click="regen_suggestions" class="btn btn-sm">
                      Regenerate suggestions
                    </.button>
                  </div>
                </div>
              <% else %>
                <.form
                  for={@manual_form}
                  id="manual-hand-form"
                  phx-change="change_hand"
                  phx-submit="submit_hand"
                  class="grid grid-cols-1 sm:grid-cols-3 gap-2"
                >
                  <.input
                    field={@manual_form[:w1]}
                    type="text"
                    label="Word 1"
                    autocomplete="off"
                    autocapitalize="off"
                    spellcheck="false"
                  />
                  <.input
                    field={@manual_form[:w2]}
                    type="text"
                    label="Word 2"
                    autocomplete="off"
                    autocapitalize="off"
                    spellcheck="false"
                  />
                  <.input
                    field={@manual_form[:w3]}
                    type="text"
                    label="Word 3"
                    autocomplete="off"
                    autocapitalize="off"
                    spellcheck="false"
                  />
                  <div class="sm:col-span-3">
                    <.button type="submit" variant="primary" class="btn btn-primary">
                      Submit hand
                    </.button>
                  </div>
                </.form>
              <% end %>

              <div class="flex items-center gap-2">
                <.button
                  phx-click="submit_hand"
                  class="btn btn-primary"
                  disabled={(@mode == :select && MapSet.size(@selection) != 3) || @round_over?}
                >
                  Submit hand
                </.button>
                <.button phx-click="deal" class="btn" disabled={false}>New round</.button>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <div class="flex items-center justify-between">
                <p class="font-medium">Opponent</p>
                <span class={[
                  "text-xs px-2 py-0.5 rounded",
                  @ai_enabled &&
                    "bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200",
                  !@ai_enabled && "bg-gray-200 dark:bg-gray-700 dark:text-gray-200"
                ]}>
                  {(@ai_enabled && "AI Enabled") || "No AI"}
                </span>
              </div>

              <%= if @round_over? && @result do %>
                <div class="mt-3 space-y-2">
                  <div>
                    <p class="text-xs text-gray-600 dark:text-gray-400">Your hand</p>
                    <div class="mt-1 flex flex-wrap gap-2">
                      <%= for w <- @result.player_hand do %>
                        <span class="px-2 py-1 rounded bg-blue-100 dark:bg-blue-900/40 text-blue-900 dark:text-blue-100 text-sm">
                          {w}
                        </span>
                      <% end %>
                    </div>
                    <p class="text-xs mt-1">
                      Score: <span class="font-semibold">{format_float(@result.player_score)}</span>
                    </p>
                  </div>

                  <%= if @ai_enabled do %>
                    <div class="mt-2">
                      <p class="text-xs text-gray-600 dark:text-gray-400">AI hand</p>
                      <div class="mt-1 flex flex-wrap gap-2">
                        <%= for w <- @result.ai_hand do %>
                          <span class="px-2 py-1 rounded bg-purple-100 dark:bg-purple-900/40 text-purple-900 dark:text-purple-100 text-sm">
                            {w}
                          </span>
                        <% end %>
                      </div>
                      <p class="text-xs mt-1">
                        Score: <span class="font-semibold">{format_float(@result.ai_score)}</span>
                      </p>
                    </div>
                  <% end %>

                  <div class={[
                    "mt-3 p-2 rounded text-sm",
                    @result.winner == :player && "bg-green-100 dark:bg-green-900/30",
                    @result.winner == :ai && "bg-red-100 dark:bg-red-900/30",
                    @result.winner == :tie && "bg-gray-200 dark:bg-gray-800"
                  ]}>
                    <%= cond do %>
                      <% @result.winner == :player -> %>
                        You win this round!
                      <% @result.winner == :ai -> %>
                        AI wins this round.
                      <% true -> %>
                        It's a tie.
                    <% end %>
                  </div>
                </div>
              <% else %>
                <p class="text-sm text-gray-600 dark:text-gray-300 mt-2">
                  Submit your hand to see results here.
                </p>
              <% end %>
            </div>

            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <p class="text-sm font-semibold mb-1">Scoring</p>
              <ul class="text-xs text-gray-600 dark:text-gray-300 space-y-1 list-disc list-inside">
                <li>Your final hand is [base1, base2] plus your 3 words.</li>
                <li>
                  Score is the average semantic similarity across your 5 words (higher is better).
                </li>
                <li>AI picks three words aiming to align with the base words.</li>
              </ul>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # === Round submission helpers ===

  defp submit_from_selection(socket) do
    if MapSet.size(socket.assigns.selection) != 3 do
      {:noreply, assign(socket, :error_message, "Please select exactly 3 words")}
    else
      player_hand = Enum.to_list(socket.assigns.selection)
      finalize_round(socket, player_hand)
    end
  end

  defp submit_from_manual(socket) do
    params = socket.assigns.manual_form.params || %{}
    w1 = normalize(params["w1"])
    w2 = normalize(params["w2"])
    w3 = normalize(params["w3"])

    words = [w1, w2, w3] |> Enum.reject(&(&1 == ""))

    cond do
      length(words) != 3 ->
        {:noreply, assign(socket, :error_message, "Please enter 3 words")}

      has_duplicates?(words) ->
        {:noreply, assign(socket, :error_message, "Words must be unique")}

      true ->
        finalize_round(socket, words)
    end
  end

  defp finalize_round(socket, player_three) do
    base = socket.assigns.base_words
    player_five = base ++ player_three
    player_score = compute_hand_score(player_five)

    {ai_hand, ai_score} =
      if socket.assigns.ai_enabled do
        ai_three = ai_pick_words(base, socket.assigns.suggestions)
        ai_five = base ++ ai_three
        {ai_five, compute_hand_score(ai_five)}
      else
        {nil, nil}
      end

    winner =
      if socket.assigns.ai_enabled do
        cond do
          player_score > ai_score -> :player
          ai_score > player_score -> :ai
          true -> :tie
        end
      else
        :player
      end

    result = %{
      player_hand: player_five,
      player_score: player_score,
      ai_hand: ai_hand || [],
      ai_score: ai_score,
      winner: winner
    }

    {:noreply,
     socket
     |> assign(:round_over?, true)
     |> assign(:result, result)
     |> assign(:error_message, nil)}
  end

  # === Internal helpers ===

  defp pick_base_words do
    vocab =
      Vocabulary.get_vocabulary()
      |> Enum.uniq()

    case vocab do
      [] ->
        {"alpha", "beta"}

      [_one] ->
        {Enum.random(vocab), "omega"}

      _ ->
        [a, b | _] = Enum.shuffle(vocab)
        {a, b}
    end
  end

  defp build_suggestions([base1, base2]) do
    candidates =
      Vocabulary.get_vocabulary()
      |> Enum.reject(&(&1 in [base1, base2]))
      |> Enum.shuffle()
      |> Enum.take(@suggestions_pool_size)

    # Batch all candidate embeddings once to minimize Serving calls
    candidate_embeddings =
      try do
        Vocabulary.embeddings_for(candidates)
      rescue
        _ -> []
      end

    target1 = GetScore.generate_target_embedding(base1, @ai_target_similarity)
    target2 = GetScore.generate_target_embedding(base2, @ai_target_similarity)

    top_half = div(@suggestions_count, 2)

    near1 =
      candidates
      |> Enum.zip(candidate_embeddings)
      |> Enum.map(fn {w, emb} ->
        cos = if emb, do: Nx.to_number(GetScore.cosine_similarity(target1, emb)), else: 0.0
        c = min(max(cos, -1.0), 1.0)
        score = 1.0 - :math.acos(c) / :math.pi()
        {w, score}
      end)
      |> Enum.sort_by(fn {_w, score} -> score end, :desc)
      |> Enum.take(top_half)
      |> Enum.map(&elem(&1, 0))

    near2 =
      candidates
      |> Enum.zip(candidate_embeddings)
      |> Enum.map(fn {w, emb} ->
        cos = if emb, do: Nx.to_number(GetScore.cosine_similarity(target2, emb)), else: 0.0
        c = min(max(cos, -1.0), 1.0)
        score = 1.0 - :math.acos(c) / :math.pi()
        {w, score}
      end)
      |> Enum.sort_by(fn {_w, score} -> score end, :desc)
      |> Enum.take(top_half)
      |> Enum.map(&elem(&1, 0))

    combined =
      (near1 ++ near2)
      |> Enum.uniq()

    need = max(@suggestions_count - length(combined), 0)
    filler = candidates |> Enum.shuffle() |> Enum.take(need)

    combined
    |> Kernel.++(filler)
    |> Enum.take(@suggestions_count)
  end

  defp safe_top_matches(query, s, candidates, opts) do
    try do
      Vocabulary.top_matches_for_desired_similarity(
        query,
        s,
        Keyword.merge(opts, candidates: candidates)
      )
    rescue
      _ -> []
    end
  end

  defp ai_pick_words([base1, base2], candidates) do
    # Score candidates by average similarity to both bases; pick the top 3
    scores =
      candidates
      |> Enum.map(fn w ->
        s1 = safe_similarity(base1, w)
        s2 = safe_similarity(base2, w)
        {w, (s1 + s2) / 2.0}
      end)
      |> Enum.sort_by(fn {_w, score} -> score end, :desc)

    chosen =
      scores
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.take(3)

    needed = max(3 - length(chosen), 0)

    if needed > 0 do
      fill =
        Vocabulary.get_vocabulary()
        |> Enum.reject(&(&1 in chosen))
        |> Enum.shuffle()
        |> Enum.take(needed)

      chosen ++ fill
    else
      chosen
    end
  end

  defp safe_similarity(a, b) do
    try do
      cos = GetScore.run(a, b)
      c = min(max(cos, -1.0), 1.0)
      1.0 - :math.acos(c) / :math.pi()
    rescue
      _ -> 0.0
    end
  end

  defp compute_hand_score(words) do
    try do
      GetScore.score_group_with_opts(words, transform: :angular)
    rescue
      _ -> 0.0
    end
  end

  defp has_duplicates?(list) do
    list
    |> Enum.map(&String.downcase/1)
    |> then(fn down -> length(down) != length(Enum.uniq(down)) end)
  end

  defp normalize(nil), do: ""

  defp normalize(s) do
    s
    |> to_string()
    |> String.trim()
  end

  defp format_float(num) when is_number(num) do
    num
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp format_float(other), do: other
end
