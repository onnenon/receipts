defmodule ReceiptsWeb.ReceiptsLiveTest do
  use ReceiptsWeb.ConnCase

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant, Player}

  test "shows each player's most played champion with win rate", %{conn: conn} do
    player = create_player("Koozie")
    create_player("No Games")

    account = create_account(player)
    ahri = create_champion("Ahri", 103)
    yasuo = create_champion("Yasuo", 157)

    create_participant(account, ahri, true)
    create_participant(account, ahri, false)
    create_participant(account, yasuo, true)

    {:ok, view, _html} = live(conn, ~p"/receipts")

    assert has_element?(view, "#player-top-champions")
    assert has_element?(view, "#player-top-champion-#{player.id}", "Ahri")
    assert has_element?(view, "#player-top-champion-#{player.id}", "2 games")
    assert has_element?(view, "#player-top-champion-#{player.id}", "50.0%")
  end

  defp create_player(name) do
    Player
    |> Ash.Changeset.for_create(:create, %{name: name, discord_id: unique_id()})
    |> Ash.create!()
  end

  defp create_account(player) do
    Account
    |> Ash.Changeset.for_create(:create, %{
      riot_puuid: "puuid-#{unique_id()}",
      riot_game_name: "Tester",
      riot_tag_line: "NA1",
      riot_region: "na1",
      riot_routing: "americas",
      player_id: player.id
    })
    |> Ash.create!()
  end

  defp create_champion(name, riot_id) do
    Champion
    |> Ash.Changeset.for_create(:create, %{
      riot_id: riot_id,
      name: name,
      key: name,
      image: "#{name}.png"
    })
    |> Ash.create!()
  end

  defp create_participant(account, champion, win) do
    match =
      Match
      |> Ash.Changeset.for_create(:create, %{
        riot_match_id: "NA1_#{unique_id()}",
        game_datetime: DateTime.utc_now(),
        game_duration_seconds: 1800,
        queue_id: 420,
        queue_type: "ranked_solo",
        raw_info: %{}
      })
      |> Ash.create!()

    MatchParticipant
    |> Ash.Changeset.for_create(:sync, %{
      account_id: account.id,
      match_id: match.id,
      champion_id: champion.id,
      kills: 1,
      deaths: 1,
      assists: 1,
      win: win,
      cs: 100,
      damage_dealt: 1000,
      vision_score: 10,
      position: "MIDDLE",
      items: [],
      raw_participant: %{}
    })
    |> Ash.create!()
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
