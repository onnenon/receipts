defmodule ReceiptsWeb.Admin.PlayersLiveTest do
  use ReceiptsWeb.ConnCase

  require Ash.Query

  alias Receipts.LoL.Player

  test "creates a new player from the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/players")

    view
    |> element("#open-new-player")
    |> render_click()

    assert has_element?(view, "#new-player-modal")
    assert has_element?(view, "#new-player-form")

    view
    |> form("#new-player-form", %{"player" => %{"name" => "Koozie", "discord_id" => unique_id()}})
    |> render_submit()

    assert has_element?(view, "#players")
    refute has_element?(view, "#new-player-modal")

    assert Player
           |> Ash.Query.filter(name == "Koozie")
           |> Ash.exists?()
  end

  test "closes the new player modal from the backdrop", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/players")

    view
    |> element("#open-new-player")
    |> render_click()

    view
    |> element("#new-player-modal-backdrop")
    |> render_click()

    refute has_element?(view, "#new-player-modal")
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
