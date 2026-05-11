defmodule Receipts.LoL.QueriesTest do
  use Receipts.DataCase

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant, Player}
  alias Receipts.LoL.Queries

  test "multi-player receipts only include games containing every selected player" do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")
    player_c = create_player("Bench")

    account_a = create_account(player_a, "A")
    account_b = create_account(player_b, "B")
    account_c = create_account(player_c, "C")

    ahri = create_champion("Ahri", 103)

    shared_match = create_match("shared", ~U[2026-05-10 12:00:00Z])
    solo_match = create_match("solo", ~U[2026-05-10 13:00:00Z])
    partial_match = create_match("partial", ~U[2026-05-10 14:00:00Z])

    create_participant(account_a, shared_match, ahri, true, kills: 6)
    create_participant(account_b, shared_match, ahri, false, kills: 2)
    create_participant(account_a, solo_match, ahri, true, kills: 20)
    create_participant(account_a, partial_match, ahri, true, kills: 10)
    create_participant(account_c, partial_match, ahri, false, kills: 1)

    assert {:ok, results} = Queries.receipts_for_players([player_a.id, player_b.id], "Ahri")

    result_by_player = Map.new(results, &{&1.player_id, &1.result})

    assert result_by_player[player_a.id].games_played == 1
    assert result_by_player[player_a.id].avg_kills == 6.0

    assert Enum.map(result_by_player[player_a.id].recent_games, & &1.match_id) == [
             shared_match.id
           ]

    assert result_by_player[player_b.id].games_played == 1
    assert result_by_player[player_b.id].avg_kills == 2.0

    assert Enum.map(result_by_player[player_b.id].recent_games, & &1.match_id) == [
             shared_match.id
           ]
  end

  test "comp suggestion context includes shared and recent non-shared role evidence" do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")

    account_a = create_account(player_a, "A")
    account_b = create_account(player_b, "B")

    ahri = create_champion("Ahri", 103)
    lulu = create_champion("Lulu", 117)

    shared_match = create_match("shared-comp", ~U[2026-05-10 12:00:00Z])
    recent_solo_match = create_match("recent-solo", ~U[2026-05-10 13:00:00Z])

    create_participant(account_a, shared_match, ahri, true, kills: 8, position: "MIDDLE")
    create_participant(account_b, shared_match, lulu, true, kills: 1, position: "UTILITY")
    create_participant(account_a, recent_solo_match, lulu, true, kills: 2, position: "UTILITY")

    assert {:ok, context} =
             Queries.comp_suggestion_context_for_players([player_a.id, player_b.id])

    assert context.shared_games.count == 1

    koozie = Enum.find(context.players, &(&1.id == player_a.id))
    kupo = Enum.find(context.players, &(&1.id == player_b.id))

    assert [%{position: "MIDDLE", games: 1, win_rate: 100.0}] = koozie.shared_positions
    assert [%{position: "UTILITY", games: 1, win_rate: 100.0}] = kupo.shared_positions

    assert [%{position: "UTILITY", games: 1, win_rate: 100.0}] =
             koozie.recent_non_shared_positions

    assert [%{champion: %{name: "Ahri"}}] = koozie.shared_top_champions
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

  defp create_match(id, game_datetime) do
    Match
    |> Ash.Changeset.for_create(:create, %{
      riot_match_id: "NA1_#{id}_#{unique_id()}",
      game_datetime: game_datetime,
      game_duration_seconds: 1800,
      queue_id: 420,
      queue_type: "ranked_solo",
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
      deaths: 1,
      assists: 3,
      win: win,
      cs: 100,
      damage_dealt: 1000,
      vision_score: 10,
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
