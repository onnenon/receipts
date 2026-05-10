defmodule Receipts.Workers.SyncAccount do
  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  # One backward page per job run; forward pass grabs up to 100 new matches.
  @backward_page_size 20
  @forward_page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    account = Ash.get!(Receipts.LoL.Account, account_id)
    tag = "#{account.riot_game_name}##{account.riot_tag_line} (#{account.riot_region})"
    champion_map = load_champion_map()

    Logger.info("[SyncAccount] Starting sync for #{tag}")

    with :ok <- forward_pass(account, champion_map, tag),
         :ok <- backward_pass(account, champion_map, tag) do
      Logger.info("[SyncAccount] Sync complete for #{tag}")
      :ok
    end
  end

  # --- Forward pass: fetch matches newer than newest_synced_at ---

  defp forward_pass(account, champion_map, tag) do
    params = forward_params(account)

    case Receipts.Riot.Client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} ->
        account
        |> Ash.Changeset.for_update(:update, %{newest_synced_at: DateTime.utc_now()})
        |> Ash.update!()

        Logger.info("[SyncAccount] Forward pass: no new matches for #{tag}, timestamp updated")
        :ok

      {:ok, match_ids} ->
        Logger.info("[SyncAccount] Forward pass: #{length(match_ids)} new match(es) for #{tag}")

        case process_match_ids(match_ids, account, champion_map, tag) do
          :ok ->
            account
            |> Ash.Changeset.for_update(:update, %{newest_synced_at: DateTime.utc_now()})
            |> Ash.update!()

            Logger.info("[SyncAccount] Forward pass complete, newest_synced_at updated for #{tag}")
            :ok

          {:snooze, _} = snooze ->
            snooze

          error ->
            error
        end

      {:error, :rate_limited} ->
        Logger.warning("[SyncAccount] Forward pass rate limited for #{tag}, snoozing 65s")
        {:snooze, 65}

      {:error, reason} ->
        Logger.error("[SyncAccount] Forward pass failed for #{tag}: #{inspect(reason)}")
        {:error, {:forward_pass, reason}}
    end
  end

  defp forward_params(%{newest_synced_at: nil}),
    do: [count: @forward_page_size]

  defp forward_params(%{newest_synced_at: ts}),
    do: [count: @forward_page_size, startTime: DateTime.to_unix(ts, :second)]

  # --- Backward pass: one page of history per job run ---

  defp backward_pass(%{history_fully_synced: true}, _champion_map, tag) do
    Logger.debug("[SyncAccount] Backward pass skipped (history fully synced) for #{tag}")
    :ok
  end

  defp backward_pass(account, champion_map, tag) do
    params = [start: account.oldest_synced_start, count: @backward_page_size]

    Logger.info("[SyncAccount] Backward pass: offset #{account.oldest_synced_start} for #{tag}")

    case Receipts.Riot.Client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} ->
        account
        |> Ash.Changeset.for_update(:update, %{history_fully_synced: true})
        |> Ash.update!()

        Logger.info("[SyncAccount] Backward pass complete: history fully synced for #{tag}")
        :ok

      {:ok, match_ids} ->
        Logger.info("[SyncAccount] Backward pass: #{length(match_ids)} match(es) to process for #{tag}")

        case process_match_ids(match_ids, account, champion_map, tag) do
          :ok ->
            new_start = account.oldest_synced_start + length(match_ids)
            fully_synced = length(match_ids) < @backward_page_size

            account
            |> Ash.Changeset.for_update(:update, %{
              oldest_synced_start: new_start,
              history_fully_synced: fully_synced
            })
            |> Ash.update!()

            Logger.info("[SyncAccount] Backward pass done: offset #{new_start}, fully_synced=#{fully_synced} for #{tag}")
            :ok

          {:snooze, _} = snooze ->
            snooze

          error ->
            error
        end

      {:error, :rate_limited} ->
        Logger.warning("[SyncAccount] Backward pass rate limited for #{tag}, snoozing 65s")
        {:snooze, 65}

      {:error, reason} ->
        Logger.error("[SyncAccount] Backward pass failed for #{tag}: #{inspect(reason)}")
        {:error, {:backward_pass, reason}}
    end
  end

  # --- Match processing ---

  defp process_match_ids(match_ids, account, champion_map, tag) do
    results = Enum.map(match_ids, &process_match(&1, account, champion_map, tag))

    # Prefer snooze over error — if we got rate limited mid-batch, snooze rather than fail
    case Enum.find(results, fn
           {:snooze, _} -> true
           {:error, _} -> true
           _ -> false
         end) do
      nil -> :ok
      found -> found
    end
  end

  defp process_match(match_id, account, champion_map, tag) do
    case Receipts.Riot.Client.get_match(match_id, account.riot_routing) do
      {:ok, match_data} ->
        info = match_data["info"]

        case find_participant(info["participants"], account.riot_puuid) do
          nil ->
            Logger.debug("[SyncAccount] #{match_id}: #{tag} not a participant, skipping")
            :ok

          participant ->
            upsert_match_and_participant(match_id, info, participant, account, champion_map)
        end

      {:error, :not_found} ->
        Logger.warning("[SyncAccount] #{match_id} not found in Riot API, skipping")
        :ok

      {:error, :rate_limited} ->
        Logger.warning("[SyncAccount] Rate limited fetching #{match_id} for #{tag}, snoozing 65s")
        {:snooze, 65}

      {:error, reason} ->
        Logger.error("[SyncAccount] Failed to fetch #{match_id} for #{tag}: #{inspect(reason)}")
        {:error, {match_id, reason}}
    end
  end

  defp find_participant(participants, puuid) do
    Enum.find(participants, fn p -> p["puuid"] == puuid end)
  end

  defp upsert_match_and_participant(match_id, info, participant, account, champion_map) do
    game_datetime = DateTime.from_unix!(info["gameStartTimestamp"], :millisecond)
    queue_id = info["queueId"]

    match =
      Receipts.LoL.Match
      |> Ash.Changeset.for_create(:sync, %{
        riot_match_id: match_id,
        game_datetime: game_datetime,
        game_duration_seconds: info["gameDuration"],
        queue_id: queue_id,
        queue_type: Receipts.LoL.Queue.from_id(queue_id),
        raw_info: info
      })
      |> Ash.create!()

    champion_riot_id = participant["championId"]

    case Map.get(champion_map, champion_riot_id) do
      nil ->
        Logger.warning("[SyncAccount] Champion ID #{champion_riot_id} not in local map for #{match_id}, skipping participant")
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

        Logger.debug("[SyncAccount] Upserted #{match_id} (#{champion.name}) for #{account.riot_game_name}##{account.riot_tag_line}")
        :ok
    end
  end

  defp load_champion_map do
    Receipts.LoL.Champion
    |> Ash.read!()
    |> Map.new(&{&1.riot_id, &1})
  end
end
