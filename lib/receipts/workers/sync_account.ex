defmodule Receipts.Workers.SyncAccount do
  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  # One backward page per job run; forward pass grabs up to 100 new matches.
  @backward_page_size 20
  @forward_page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    account = Ash.get!(Receipts.LoL.Account, account_id)
    champion_map = load_champion_map()

    with :ok <- forward_pass(account, champion_map),
         :ok <- backward_pass(account, champion_map) do
      :ok
    end
  end

  # --- Forward pass: fetch matches newer than newest_synced_at ---

  defp forward_pass(account, champion_map) do
    params = forward_params(account)

    case Receipts.Riot.Client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} ->
        :ok

      {:ok, match_ids} ->
        case process_match_ids(match_ids, account, champion_map) do
          :ok ->
            account
            |> Ash.Changeset.for_update(:update, %{newest_synced_at: DateTime.utc_now()})
            |> Ash.update!()

            :ok

          error ->
            error
        end

      {:error, :rate_limited} ->
        {:snooze, 65}

      {:error, reason} ->
        {:error, {:forward_pass, reason}}
    end
  end

  defp forward_params(%{newest_synced_at: nil}),
    do: [count: @forward_page_size]

  defp forward_params(%{newest_synced_at: ts}),
    do: [count: @forward_page_size, startTime: DateTime.to_unix(ts, :second)]

  # --- Backward pass: one page of history per job run ---

  defp backward_pass(%{history_fully_synced: true}, _champion_map), do: :ok

  defp backward_pass(account, champion_map) do
    params = [start: account.oldest_synced_start, count: @backward_page_size]

    case Receipts.Riot.Client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} ->
        account
        |> Ash.Changeset.for_update(:update, %{history_fully_synced: true})
        |> Ash.update!()

        :ok

      {:ok, match_ids} ->
        case process_match_ids(match_ids, account, champion_map) do
          :ok ->
            new_start = account.oldest_synced_start + length(match_ids)
            fully_synced = length(match_ids) < @backward_page_size

            account
            |> Ash.Changeset.for_update(:update, %{
              oldest_synced_start: new_start,
              history_fully_synced: fully_synced
            })
            |> Ash.update!()

            :ok

          error ->
            error
        end

      {:error, :rate_limited} ->
        {:snooze, 65}

      {:error, reason} ->
        {:error, {:backward_pass, reason}}
    end
  end

  # --- Match processing ---

  defp process_match_ids(match_ids, account, champion_map) do
    results =
      Enum.map(match_ids, fn match_id ->
        process_match(match_id, account, champion_map)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  defp process_match(match_id, account, champion_map) do
    case Receipts.Riot.Client.get_match(match_id, account.riot_routing) do
      {:ok, match_data} ->
        info = match_data["info"]

        case find_participant(info["participants"], account.riot_puuid) do
          nil ->
            :ok

          participant ->
            upsert_match_and_participant(match_id, info, participant, account, champion_map)
        end

      {:error, :not_found} ->
        Logger.warning("Match #{match_id} not found in API, skipping")
        :ok

      {:error, :rate_limited} ->
        {:error, :rate_limited}

      {:error, reason} ->
        Logger.error("Failed to fetch match #{match_id}: #{inspect(reason)}")
        {:error, {match_id, reason}}
    end
  end

  defp find_participant(participants, puuid) do
    Enum.find(participants, fn p -> p["puuid"] == puuid end)
  end

  defp upsert_match_and_participant(match_id, info, participant, account, champion_map) do
    game_datetime = DateTime.from_unix!(info["gameStartTimestamp"], :millisecond)

    match =
      Receipts.LoL.Match
      |> Ash.Changeset.for_create(:sync, %{
        riot_match_id: match_id,
        game_datetime: game_datetime,
        game_duration_seconds: info["gameDuration"],
        queue_id: info["queueId"],
        raw_info: info
      })
      |> Ash.create!()

    champion_riot_id = participant["championId"]

    case Map.get(champion_map, champion_riot_id) do
      nil ->
        Logger.warning("Champion #{champion_riot_id} not in champion map, skipping participant")
        :ok

      champion ->
        items = Enum.map(0..6, &(participant["item#{&1}"] || 0))
        cs = (participant["totalMinionsKilled"] || 0) + (participant["neutralMinionsKilled"] || 0)
        position = participant["teamPosition"]

        Receipts.LoL.MatchParticipant
        |> Ash.Changeset.for_create(:sync, %{
          match_id: match.id,
          account_id: account.id,
          champion_id: champion.id,
          kills: participant["kills"],
          deaths: participant["deaths"],
          assists: participant["assists"],
          win: participant["win"],
          cs: cs,
          damage_dealt: participant["totalDamageDealtToChampions"],
          vision_score: participant["visionScore"],
          position: if(position == "", do: nil, else: position),
          team_id: participant["teamId"],
          items: items,
          raw_participant: participant
        })
        |> Ash.create!()

        :ok
    end
  end

  defp load_champion_map do
    Receipts.LoL.Champion
    |> Ash.read!()
    |> Map.new(&{&1.riot_id, &1})
  end
end
