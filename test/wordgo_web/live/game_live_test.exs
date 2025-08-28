defmodule WordgoWeb.GameLiveTest do
  use WordgoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Game LiveView" do
    test "renders the game board", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      assert has_element?(view, "h1", "Word Game")
      assert has_element?(view, "h2", "Player: Test Player")
      assert has_element?(view, "h2", "Game Board")
    end

    test "allows selecting a position", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      # Click on a board position
      view |> element("button[phx-value-x='3'][phx-value-y='4']") |> render_click()

      # Check that the position is selected
      assert has_element?(view, "p", "Selected position: 3, 4")
    end

    test "allows placing a word", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      # Select a position
      view |> element("button[phx-value-x='3'][phx-value-y='4']") |> render_click()

      # Fill in the word form and submit
      view
      |> form("form", %{word: "hello"})
      |> render_submit()

      # Check that the word was placed
      assert has_element?(view, "td", "hello")
      assert has_element?(view, "td", "3, 4")
      assert has_element?(view, "li", "hello")

      # Score is now based on semantic similarity, not just word length
      # Just check that some score is displayed
      assert view |> element("p", ~r/Score: \d+/) |> has_element?()
    end

    test "prevents placing a word on an occupied position", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      # Select a position and place a word
      view |> element("button[phx-value-x='3'][phx-value-y='4']") |> render_click()

      view
      |> form("form", %{word: "hello"})
      |> render_submit()

      # Try to select the same position
      view |> element("button[phx-value-x='3'][phx-value-y='4']") |> render_click()

      # Check for error message
      assert has_element?(view, "div.bg-red-100", "That position is already occupied")
    end

    test "resets the game", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      # Place a word
      view |> element("button[phx-value-x='3'][phx-value-y='4']") |> render_click()

      view
      |> form("form", %{word: "hello"})
      |> render_submit()

      # Check that the word was placed
      assert has_element?(view, "td", "hello")

      # Reset the game
      view |> element("button", "Reset Game") |> render_click()

      # Check that the board is empty
      refute has_element?(view, "td", "hello")
      assert has_element?(view, "p", "Score: 0")
      assert has_element?(view, "p", "No words have been placed yet")
    end
  end
end
