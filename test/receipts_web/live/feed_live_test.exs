defmodule ReceiptsWeb.FeedLiveTest do
  use ReceiptsWeb.ConnCase

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant, Player}

  test "feed page shows recent ranked games grouped by match with all registered players", %{
    conn: conn
  } do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")

    account_a = create_account(player_a, "A")
    account_b = create_account(player_b, "B")

    ahri = create_champion("Ahri", 103)
    lulu = create_champion("Lulu", 117)

    shared_match = create_match("feed-shared", ~U[2026-05-10 13:00:00Z])

    create_participant(account_a, shared_match, ahri, true,
      kills: 6,
      deaths: 2,
      assists: 9,
      cs: 150,
      damage_dealt: 12_345,
      vision_score: 18
    )

    create_participant(account_b, shared_match, lulu, false,
      kills: 1,
      deaths: 7,
      assists: 14,
      cs: 35,
      damage_dealt: 4_321,
      vision_score: 42,
      position: "UTILITY"
    )

    {:ok, view, _html} = live(conn, ~p"/feed")

    assert has_element?(view, "#recent-games-feed")
    assert has_element?(view, "#recent-game-#{shared_match.id}", "2 players together")
    assert has_element?(view, "#recent-game-#{shared_match.id}", "Ranked Solo/Duo")
    assert has_element?(view, "#recent-game-#{shared_match.id}", "30:00")

    assert has_element?(
             view,
             "#recent-game-#{shared_match.id}-player-#{player_a.id}",
             "Koozie"
           )

    assert has_element?(
             view,
             "#recent-game-#{shared_match.id}-player-#{player_a.id}",
             "6/2/9"
           )

    assert has_element?(
             view,
             "#recent-game-#{shared_match.id}-player-#{player_a.id}",
             "12,345"
           )

    assert has_element?(
             view,
             "#recent-game-#{shared_match.id}-player-#{player_b.id}",
             "Lulu"
           )

    assert has_element?(
             view,
             "#recent-game-#{shared_match.id}-player-#{player_b.id}",
             "Loss"
           )
  end

  test "feed page excludes non-ranked games", %{conn: conn} do
    player = create_player("Koozie")
    account = create_account(player, "A")
    ahri = create_champion("Ahri", 103)

    ranked_match = create_match("ranked-feed", ~U[2026-05-10 13:00:00Z])

    normal_match =
      create_match("normal-feed", ~U[2026-05-10 14:00:00Z],
        queue_id: 400,
        queue_type: "normal_draft"
      )

    create_participant(account, ranked_match, ahri, true, kills: 6)
    create_participant(account, normal_match, ahri, true, kills: 20)

    {:ok, view, _html} = live(conn, ~p"/feed")

    assert has_element?(view, "#recent-game-#{ranked_match.id}")
    refute has_element?(view, "#recent-game-#{normal_match.id}")
    refute has_element?(view, "#recent-games-feed", "Normal Draft")
  end

  defp create_player(name) do
    Player
    |> Ash.Changeset.for_create(:create, %{name: name, discord_id: unique_id()})
    |> Ash.create!()
  end

  defp create_account(player, suffix) do
    Account
    |> Ash.Changeset.for_create(:create, %{
      riot_puuid: "puuid-#{suffix}-#{unique_id()}",
      riot_game_name: "Tester#{suffix}",
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

  defp create_match(id, game_datetime, opts \\ []) do
    Match
    |> Ash.Changeset.for_create(:create, %{
      riot_match_id: "NA1_#{id}_#{unique_id()}",
      game_datetime: game_datetime,
      game_duration_seconds: 1800,
      queue_id: Keyword.get(opts, :queue_id, 420),
      queue_type: Keyword.get(opts, :queue_type, "ranked_solo"),
      raw_info: %{}
    })
    |> Ash.create!()
  end

  defp create_participant(account, match, champion, win, opts) do
    MatchParticipant
    |> Ash.Changeset.for_create(:sync, %{
      account_id: account.id,
      match_id: match.id,
      champion_id: champion.id,
      kills: Keyword.fetch!(opts, :kills),
      deaths: Keyword.get(opts, :deaths, 1),
      assists: Keyword.get(opts, :assists, 3),
      win: win,
      cs: Keyword.get(opts, :cs, 100),
      damage_dealt: Keyword.get(opts, :damage_dealt, 1000),
      vision_score: Keyword.get(opts, :vision_score, 10),
      position: Keyword.get(opts, :position, "MIDDLE"),
      items: [],
      game_datetime: match.game_datetime,
      queue_type: match.queue_type,
      raw_participant: %{}
    })
    |> Ash.create!()
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
