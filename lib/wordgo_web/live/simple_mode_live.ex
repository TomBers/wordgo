defmodule WordgoWeb.SimpleModeLive do
  use WordgoWeb, :live_view

  alias Wordgo.WordToVec.{GetScore, Vocabulary}

  @default_threshold 0.6
  @default_lives 3

  # === Lifecycle ===

  @impl true
  def mount(params, _session, socket) do
    threshold =
      params["threshold"]
      |> parse_float(@default_threshold)
      |> clamp(0.0, 1.0)

    lives =
      params["lives"]
      |> parse_int(@default_lives)
      |> max(1)

    seed = pick_seed_word()

    words = [seed]
    score = compute_score(words)

    form = Phoenix.Component.to_form(%{"text" => ""}, as: :word)

    socket =
      socket
      |> assign(:current_scope, "simple")
      |> assign(:seed_word, seed)
      |> assign(:words, words)
      |> assign(:score, score)
      |> assign(:threshold, threshold)
      |> assign(:lives, lives)
      |> assign(:max_lives, lives)
      |> assign(:game_over?, false)
      |> assign(:error_message, nil)
      |> assign(:form, form)

    {:ok, socket}
  end

  # === Events ===

  @impl true
  def handle_event("change", %{"word" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :form, Phoenix.Component.to_form(%{"text" => text}, as: :word))}
  end

  @impl true
  def handle_event("add", %{"word" => %{"text" => raw_text}}, socket) do
    if socket.assigns.game_over? do
      {:noreply, socket}
    else
      text =
        raw_text
        |> to_string()
        |> String.trim()

      cond do
        text == "" ->
          {:noreply, put_error(socket, "Please enter a word")}

        contains_space?(text) ->
          {:noreply, put_error(socket, "Only single words are allowed")}

        word_exists?(socket.assigns.words, text) ->
          {:noreply, put_error(socket, "That word is already in the list")}

        true ->
          new_words = socket.assigns.words ++ [text]
          new_score = compute_score(new_words)

          {lives, game_over?} =
            if new_score < socket.assigns.threshold do
              new_lives = max(socket.assigns.lives - 1, 0)
              {new_lives, new_lives == 0}
            else
              {socket.assigns.lives, false}
            end

          {:noreply,
           socket
           |> assign(:words, new_words)
           |> assign(:score, new_score)
           |> assign(:lives, lives)
           |> assign(:game_over?, game_over?)
           |> assign(:error_message, nil)
           |> assign(:form, Phoenix.Component.to_form(%{"text" => ""}, as: :word))}
      end
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    seed = pick_seed_word()
    words = [seed]
    score = compute_score(words)

    {:noreply,
     socket
     |> assign(:seed_word, seed)
     |> assign(:words, words)
     |> assign(:score, score)
     |> assign(:lives, socket.assigns.max_lives)
     |> assign(:game_over?, false)
     |> assign(:error_message, nil)
     |> assign(:form, Phoenix.Component.to_form(%{"text" => ""}, as: :word))}
  end

  # === Rendering ===

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-4 py-6">
        <h1 class="text-2xl font-bold mb-2">Simple Mode</h1>
        <p class="text-sm text-gray-600 dark:text-gray-300 mb-4">
          Start from the seed word and add related words. Keep the average similarity above the threshold to avoid losing lives.
        </p>

        <div class="grid gap-4 md:grid-cols-3">
          <div class="md:col-span-2 space-y-3">
            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <div class="flex items-center justify-between mb-2">
                <div>
                  <p class="text-xs text-gray-500 dark:text-gray-400">Seed word</p>
                  <p class="text-lg font-semibold">{@seed_word}</p>
                </div>
                <div class="text-right">
                  <p class="text-xs text-gray-500 dark:text-gray-400">Threshold</p>
                  <p class="text-lg font-semibold">{format_float(@threshold)}</p>
                </div>
              </div>

              <div class="mt-2">
                <p class="text-xs text-gray-500 dark:text-gray-400 mb-1">Your words</p>
                <div class="flex flex-wrap gap-2">
                  <%= for w <- @words do %>
                    <span class="px-2 py-1 rounded bg-blue-100 dark:bg-blue-900/40 text-blue-900 dark:text-blue-100 text-sm">
                      {w}
                    </span>
                  <% end %>
                </div>
              </div>
            </div>

            <div class={[
              "rounded-lg border p-4",
              score_ok?(@score, @threshold) &&
                "bg-green-50 dark:bg-green-900/20 border-green-300 dark:border-green-700",
              !score_ok?(@score, @threshold) &&
                "bg-red-50 dark:bg-red-900/20 border-red-300 dark:border-red-700"
            ]}>
              <p class="text-xs text-gray-600 dark:text-gray-300">Average similarity (0..1)</p>
              <p class={[
                "text-2xl font-bold",
                score_ok?(@score, @threshold) && "text-green-700 dark:text-green-300",
                !score_ok?(@score, @threshold) && "text-red-700 dark:text-red-300"
              ]}>
                {format_float(@score)}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                Dropping below the threshold costs one life.
              </p>
            </div>

            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <%= if @error_message do %>
                <div class="mb-2 px-3 py-2 rounded text-sm bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200 border border-red-300 dark:border-red-700">
                  {@error_message}
                </div>
              <% end %>

              <.form
                for={@form}
                id="simple-word-form"
                phx-change="change"
                phx-submit="add"
                class="flex items-end gap-2"
              >
                <div class="flex-1">
                  <.input
                    field={@form[:text]}
                    type="text"
                    label="Add a related word"
                    placeholder="e.g. feline, kitten, pet"
                    disabled={@game_over?}
                    autocomplete="off"
                    autocapitalize="off"
                    spellcheck="false"
                  />
                </div>
                <.button type="submit" variant="primary" disabled={@game_over?}>
                  Add
                </.button>
              </.form>
            </div>
          </div>

          <div class="space-y-3">
            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <p class="text-xs text-gray-500 dark:text-gray-400">Lives</p>
              <div class="mt-1 flex items-center gap-1">
                <%= for _ <- 1..@lives do %>
                  <span class="text-red-500">❤</span>
                <% end %>
                <%= for _ <- 1..(@max_lives - @lives) do %>
                  <span class="text-gray-300 dark:text-gray-600">❤</span>
                <% end %>
              </div>

              <%= if @game_over? do %>
                <div class="mt-3 p-2 rounded bg-red-100 dark:bg-red-900/30 border border-red-300 dark:border-red-700 text-sm text-red-800 dark:text-red-200">
                  Game Over — you ran out of lives.
                </div>
              <% end %>

              <div class="mt-3">
                <button phx-click="reset" class="btn btn-sm btn-primary w-full">
                  Reset
                </button>
              </div>
            </div>

            <div class="rounded-lg border p-4 bg-white dark:bg-gray-800">
              <p class="text-sm font-semibold mb-1">How scoring works</p>
              <ul class="text-xs text-gray-600 dark:text-gray-300 space-y-1 list-disc list-inside">
                <li>Score reflects how semantically related your words are as a whole.</li>
                <li>The displayed score is an average between 0 and 1.</li>
                <li>Adding an unrelated word may drop the score and cost a life.</li>
                <li>Aim to keep the score above the threshold.</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # === Helpers ===

  defp pick_seed_word do
    vocab = Vocabulary.get_vocabulary()

    case vocab do
      [] -> "start"
      list -> Enum.random(list)
    end
  end

  defp word_exists?(words, new_word) do
    down = String.downcase(new_word)
    Enum.any?(words, fn w -> String.downcase(w) == down end)
  end

  defp contains_space?(text) do
    String.contains?(text, [" ", "\t", "\n"])
  end

  defp put_error(socket, msg) do
    assign(socket, :error_message, msg)
  end

  defp score_ok?(score, threshold) do
    score >= threshold
  end

  defp format_float(num) when is_number(num) do
    num
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp format_float(other), do: other

  # Compute the average similarity of the list (0..1).
  # Falls back to 0.0 on errors.
  defp compute_score(words) when is_list(words) do
    case words do
      [] ->
        0.0

      list ->
        try do
          # GetScore.score_group/1 returns the sum of cosine similarities of the average embedding to each word.
          # Turn it into an average to keep the score in [0, 1] regardless of list length.
          sum = GetScore.score_group(list)
          n = max(length(list), 1)
          sum / n
        rescue
          _ -> 0.0
        end
    end
  end

  defp parse_float(nil, default), do: default

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_float(val, _default) when is_number(val), do: val

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp clamp(num, min_v, max_v) when is_number(num) do
    num
    |> max(min_v)
    |> min(max_v)
  end
end
