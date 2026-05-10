defmodule ReceiptsWeb.Admin.PlayerDetailLiveTest do
  use ReceiptsWeb.ConnCase

  require Ash.Query

  alias Receipts.LoL.{Account, Player}
  alias Receipts.RiotClientStub

  setup do
    RiotClientStub.reset()
    RiotClientStub.put_match_ids(fn _puuid, _routing, _opts -> {:ok, []} end)

    player =
      Player
      |> Ash.Changeset.for_create(:create, %{name: "Test Player", discord_id: unique_id()})
      |> Ash.create!()

    account =
      Account
      |> Ash.Changeset.for_create(:create, %{
        riot_puuid: "existing-#{unique_id()}",
        riot_game_name: "Existing",
        riot_tag_line: "NA1",
        riot_region: "na1",
        riot_routing: "americas",
        player_id: player.id
      })
      |> Ash.create!()

    %{player: player, account: account}
  end

  test "adds another account under an existing player", %{conn: conn, player: player} do
    RiotClientStub.put_accounts_by_riot_id(fn
      "Second", "NA1", "americas" -> {:ok, %{"puuid" => "second-#{unique_id()}"}}
      _game_name, _tag_line, _routing -> {:error, :not_found}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/players/#{player.id}")

    view
    |> element("#toggle-add-account")
    |> render_click()

    view
    |> form("#add-account-form", %{"account" => %{"riot_id" => "Second#NA1", "region" => "NA"}})
    |> render_submit()

    assert has_element?(view, "#accounts")

    player_id = player.id

    accounts =
      Account
      |> Ash.Query.filter(player_id == ^player_id)
      |> Ash.read!()

    assert length(accounts) == 2
    assert Enum.any?(accounts, &(&1.riot_game_name == "Second" && &1.riot_tag_line == "NA1"))
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
