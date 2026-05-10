defmodule Receipts.Workers.SyncAccountTest do
  use Receipts.DataCase

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant, Player}
  alias Receipts.RiotClientStub
  alias Receipts.Workers.SyncAccount

  setup do
    RiotClientStub.reset()

    player =
      Player
      |> Ash.Changeset.for_create(:create, %{name: "Test Player", discord_id: unique_id()})
      |> Ash.create!()

    account =
      Account
      |> Ash.Changeset.for_create(:create, %{
        riot_puuid: unique_id(),
        riot_game_name: "Tester",
        riot_tag_line: "NA1",
        riot_region: "na1",
        riot_routing: "americas",
        player_id: player.id
      })
      |> Ash.create!()

    champion =
      Champion
      |> Ash.Changeset.for_create(:create, %{
        riot_id: System.unique_integer([:positive]),
        name: "Test Champ #{unique_id()}",
        key: "TestChamp#{unique_id()}",
        image: "test.png"
      })
      |> Ash.create!()

    %{account: account, champion: champion}
  end

  test "forward pass pages through more than 100 matches after an existing checkpoint", %{
    account: account,
    champion: champion
  } do
    checkpoint = ~U[2026-05-01 00:00:00Z]
    base_time = ~U[2026-05-10 12:00:00Z]

    account =
      update_account!(account, %{newest_synced_at: checkpoint, history_fully_synced: true})

    matches = build_matches(account, champion, 101, base_time)

    stub_match_ids_from_matches(matches)
    stub_match_details(matches)

    assert :ok = SyncAccount.perform(%Oban.Job{args: %{"account_id" => account.id}})

    account = Ash.get!(Account, account.id)
    assert DateTime.compare(account.newest_synced_at, base_time) == :eq

    assert participant_count(account) == 101

    calls = RiotClientStub.match_id_calls()
    assert length(calls) == 2
    assert {_puuid, _routing, first_opts} = Enum.at(calls, 0)
    assert {_puuid, _routing, second_opts} = Enum.at(calls, 1)
    assert Keyword.fetch!(first_opts, :startTime) == DateTime.to_unix(checkpoint, :second)
    assert Keyword.has_key?(second_opts, :endTime)
  end

  test "first sync does not make the forward pass traverse full history", %{
    account: account,
    champion: champion
  } do
    base_time = ~U[2026-05-10 12:00:00Z]
    account = update_account!(account, %{history_fully_synced: true})
    matches = build_matches(account, champion, 150, base_time)

    stub_match_ids_from_matches(matches)
    stub_match_details(matches)

    assert :ok = SyncAccount.perform(%Oban.Job{args: %{"account_id" => account.id}})

    assert participant_count(account) == 100

    assert [{_puuid, _routing, opts}] = RiotClientStub.match_id_calls()
    refute Keyword.has_key?(opts, :endTime)
  end

  test "missing participant fetch errors do not advance the backward cursor", %{account: account} do
    checkpoint = ~U[2026-05-10 12:00:00Z]
    account = update_account!(account, %{newest_synced_at: checkpoint, oldest_synced_start: 0})

    match =
      Match
      |> Ash.Changeset.for_create(:sync, %{
        riot_match_id: "NA1_existing",
        game_datetime: ~U[2026-05-09 12:00:00Z],
        game_duration_seconds: 1800,
        queue_id: 420,
        queue_type: "ranked_solo",
        raw_info: %{}
      })
      |> Ash.create!()

    RiotClientStub.put_match_ids(fn _puuid, _routing, opts ->
      if Keyword.has_key?(opts, :startTime) do
        {:ok, []}
      else
        {:ok, [match.riot_match_id]}
      end
    end)

    match_id = match.riot_match_id
    RiotClientStub.put_matches(fn ^match_id, _routing -> {:error, :rate_limited} end)

    assert {:snooze, 65} = SyncAccount.perform(%Oban.Job{args: %{"account_id" => account.id}})

    account = Ash.get!(Account, account.id)
    assert account.oldest_synced_start == 0
    assert participant_count(account) == 0
  end

  test "backward pass continues from the oldest synced timestamp instead of an offset", %{
    account: account,
    champion: champion
  } do
    newest_synced_at = ~U[2026-05-10 12:00:00Z]
    oldest_synced_at = ~U[2026-05-09 12:00:00Z]

    account =
      update_account!(account, %{
        newest_synced_at: newest_synced_at,
        oldest_synced_start: 50,
        oldest_synced_at: oldest_synced_at,
        history_fully_synced: false
      })

    matches = build_matches(account, champion, 10, DateTime.add(oldest_synced_at, -60, :second))

    stub_match_ids_from_matches(matches)
    stub_match_details(matches)

    assert :ok = SyncAccount.perform(%Oban.Job{args: %{"account_id" => account.id}})

    account = Ash.get!(Account, account.id)
    assert account.oldest_synced_start == 60

    assert DateTime.compare(
             account.oldest_synced_at,
             DateTime.add(oldest_synced_at, -600, :second)
           ) == :eq

    assert [
             {_forward_puuid, _forward_routing, forward_opts},
             {_backward_puuid, _backward_routing, backward_opts}
           ] = RiotClientStub.match_id_calls()

    assert Keyword.fetch!(forward_opts, :startTime) == DateTime.to_unix(newest_synced_at, :second)

    assert Keyword.fetch!(backward_opts, :endTime) ==
             DateTime.to_unix(oldest_synced_at, :second) - 1

    refute Keyword.has_key?(backward_opts, :start)
  end

  defp build_matches(account, champion, count, base_time) do
    0..(count - 1)
    |> Enum.map(fn index ->
      game_datetime = DateTime.add(base_time, -index * 60, :second)
      match_id = "NA1_#{index}"

      {match_id,
       %{
         game_datetime: game_datetime,
         data: %{
           "info" => %{
             "gameStartTimestamp" => DateTime.to_unix(game_datetime, :millisecond),
             "gameDuration" => 1800,
             "queueId" => 420,
             "participants" => [
               %{
                 "puuid" => account.riot_puuid,
                 "championId" => champion.riot_id,
                 "kills" => 7,
                 "deaths" => 3,
                 "assists" => 9,
                 "win" => true,
                 "totalMinionsKilled" => 180,
                 "neutralMinionsKilled" => 12,
                 "totalDamageDealtToChampions" => 22_000,
                 "visionScore" => 28,
                 "teamPosition" => "MIDDLE",
                 "teamId" => 100,
                 "item0" => 1001,
                 "item1" => 1002,
                 "item2" => 1003,
                 "item3" => 1004,
                 "item4" => 1005,
                 "item5" => 1006,
                 "item6" => 3364
               }
             ]
           }
         }
       }}
    end)
  end

  defp stub_match_ids_from_matches(matches) do
    RiotClientStub.put_match_ids(fn _puuid, _routing, opts ->
      start_time = Keyword.get(opts, :startTime, 0)
      end_time = Keyword.get(opts, :endTime, :infinity)
      start_offset = Keyword.get(opts, :start, 0)
      count = Keyword.fetch!(opts, :count)

      ids =
        matches
        |> Enum.filter(fn {_match_id, %{game_datetime: game_datetime}} ->
          timestamp = DateTime.to_unix(game_datetime, :second)
          timestamp >= start_time && (end_time == :infinity || timestamp <= end_time)
        end)
        |> Enum.drop(start_offset)
        |> Enum.take(count)
        |> Enum.map(fn {match_id, _match} -> match_id end)

      {:ok, ids}
    end)
  end

  defp stub_match_details(matches) do
    match_map = Map.new(matches, fn {match_id, match} -> {match_id, match.data} end)

    RiotClientStub.put_matches(fn match_id, _routing ->
      {:ok, Map.fetch!(match_map, match_id)}
    end)
  end

  defp participant_count(account) do
    MatchParticipant
    |> Ash.read!()
    |> Enum.count(&(&1.account_id == account.id))
  end

  defp update_account!(account, attrs) do
    account
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!()
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
