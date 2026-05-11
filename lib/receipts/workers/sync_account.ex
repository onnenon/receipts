defmodule Receipts.Workers.SyncAccount do
  use Oban.Worker, queue: :sync, max_attempts: 3

  require Logger

  # One backward page per job run; forward pass grabs up to 100 new matches.
  @backward_page_size 50
  @forward_page_size 100
  @riot_client Application.compile_env(:receipts, :riot_client, Receipts.Riot.Client)
  @data_dragon Application.compile_env(:receipts, :data_dragon, Receipts.Riot.DataDragon)
  @refreshed_champion_map_key {__MODULE__, :refreshed_champion_map}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    Process.delete(@refreshed_champion_map_key)

    try do
      sync_account(account_id)
    after
      Process.delete(@refreshed_champion_map_key)
    end
  end

  defp sync_account(account_id) do
    account = Ash.get!(Receipts.LoL.Account, account_id)
    tag = "#{account.riot_game_name}##{account.riot_tag_line} (#{account.riot_region})"
    champion_map = load_champion_map()

    Logger.info("[SyncAccount] Starting sync for #{tag}")

    if champion_map == %{} do
      Logger.error(
        "[SyncAccount] Champion data is missing; run Data Dragon sync before account sync"
      )

      {:error, :champions_not_synced}
    else
      backfill_stored_matches(account, champion_map, tag)

      # Forward pass handles new matches; backward pass handles historical backfill.
      # We run forward first to ensure newest_synced_at is up to date.
      case forward_pass(account, champion_map, tag) do
        {:ok, account} ->
          case backward_pass(account, champion_map, tag) do
            :ok ->
              account = mark_sync_complete(account)
              fetch_rank(account, tag)
              Logger.info("[SyncAccount] Sync complete for #{tag}")
              :ok

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  defp mark_sync_complete(account) do
    account
    |> Ash.Changeset.for_update(:update, %{last_synced_at: DateTime.utc_now()})
    |> Ash.update!()
  end

  defp fetch_rank(account, tag) do
    case @riot_client.get_rank_by_puuid(account.riot_puuid, account.riot_region) do
      {:ok, entries} ->
        entry =
          Enum.find(entries, &(&1["queueType"] == "RANKED_SOLO_5x5")) ||
            Enum.find(entries, &(&1["queueType"] == "RANKED_FLEX_SR"))

        attrs =
          if entry do
            %{
              rank_tier: entry["tier"],
              rank_division: entry["rank"],
              rank_lp: entry["leaguePoints"]
            }
          else
            %{rank_tier: nil, rank_division: nil, rank_lp: nil}
          end

        account |> Ash.Changeset.for_update(:update, attrs) |> Ash.update!()

        if entry,
          do:
            Logger.info(
              "[SyncAccount] Rank updated: #{entry["tier"]} #{entry["rank"]} for #{tag}"
            )

      {:error, reason} ->
        Logger.warning("[SyncAccount] Could not fetch rank for #{tag}: #{inspect(reason)}")
    end
  end

  # --- Forward pass: fetch ALL matches newer than newest_synced_at ---

  defp forward_pass(account, champion_map, tag) do
    # startTime is inclusive in Riot API.
    # To avoid re-fetching the same "newest" match, we could use +1s, 
    # but Riot IDs are unique and we upsert, so it is safer to just fetch.
    start_time =
      if account.newest_synced_at,
        do: DateTime.to_unix(account.newest_synced_at, :second),
        else: nil

    case fetch_and_process_forward(account, champion_map, tag, start_time, nil, nil) do
      {:ok, newest_match_at} ->
        # Only advance to an observed match timestamp. If there were no matches, preserve an
        # existing checkpoint so a transiently delayed Riot result cannot be skipped.
        new_ts = newest_match_at || account.newest_synced_at || DateTime.utc_now()

        account =
          account
          |> Ash.Changeset.for_update(:update, %{newest_synced_at: new_ts})
          |> Ash.update!()

        {:ok, account}

      error ->
        error
    end
  end

  # Recursive helper to handle more than 100 new matches.
  defp fetch_and_process_forward(account, champion_map, tag, start_time, end_time, newest_so_far) do
    params = [count: @forward_page_size]
    params = if start_time, do: params ++ [startTime: start_time], else: params
    params = if end_time, do: params ++ [endTime: end_time], else: params

    case @riot_client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} ->
        {:ok, newest_so_far}

      {:ok, match_ids} ->
        Logger.info(
          "[SyncAccount] Forward pass: processing #{length(match_ids)} match(es) for #{tag}"
        )

        case process_match_ids(match_ids, account, champion_map, tag) do
          :ok ->
            with {:ok, newest_so_far} <-
                   update_newest_so_far(newest_so_far, match_ids, account.riot_routing) do
              if start_time && length(match_ids) == @forward_page_size do
                # Possible more matches between our checkpoint and the oldest in this batch.
                # We fetch the timestamp of the oldest match in this batch to use as endTime for next.
                case get_match_timestamp(List.last(match_ids), account.riot_routing) do
                  {:ok, oldest_ts} ->
                    fetch_and_process_forward(
                      account,
                      champion_map,
                      tag,
                      start_time,
                      DateTime.to_unix(oldest_ts, :second) - 1,
                      newest_so_far
                    )

                  {:error, _} = error ->
                    error
                end
              else
                {:ok, newest_so_far}
              end
            end

          error ->
            error
        end

      {:error, :rate_limited} ->
        {:snooze, 65}

      {:error, reason} ->
        {:error, {:forward_pass, reason}}
    end
  end

  defp get_newest_match_timestamp(match_ids, routing) do
    # Riot returns newest first, so first ID is newest.
    match_ids
    |> List.first()
    |> get_match_timestamp(routing)
  end

  defp update_newest_so_far(nil, match_ids, routing),
    do: get_newest_match_timestamp(match_ids, routing)

  defp update_newest_so_far(newest_so_far, _match_ids, _routing), do: {:ok, newest_so_far}

  defp get_match_timestamp(match_id, routing) do
    case Receipts.Repo.get_by(Receipts.LoL.Match, riot_match_id: match_id) do
      %{game_datetime: game_datetime} ->
        {:ok, game_datetime}

      nil ->
        case @riot_client.get_match(match_id, routing) do
          {:ok, data} ->
            {:ok, DateTime.from_unix!(data["info"]["gameStartTimestamp"], :millisecond)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # --- Backward pass: one page of history per job run ---

  defp backward_pass(%{history_fully_synced: true}, _champion_map, tag) do
    Logger.debug("[SyncAccount] Backward pass skipped (history fully synced) for #{tag}")
    :ok
  end

  defp backward_pass(account, champion_map, tag) do
    params = backward_params(account)

    Logger.info(
      "[SyncAccount] Backward pass: before #{account.oldest_synced_at || "current tip"} for #{tag}"
    )

    case @riot_client.get_match_ids(account.riot_puuid, account.riot_routing, params) do
      {:ok, []} when not is_nil(account.oldest_synced_at) ->
        account
        |> Ash.Changeset.for_update(:update, %{history_fully_synced: true})
        |> Ash.update!()

        Logger.info("[SyncAccount] Backward pass complete: history fully synced for #{tag}")
        :ok

      {:ok, []} ->
        Logger.warning(
          "[SyncAccount] Backward pass returned no matches before a history cursor exists for #{tag}; preserving incomplete history"
        )

        :ok

      {:ok, match_ids} ->
        Logger.info(
          "[SyncAccount] Backward pass: #{length(match_ids)} match(es) to process for #{tag}"
        )

        case process_match_ids(match_ids, account, champion_map, tag) do
          :ok ->
            case get_match_timestamp(List.last(match_ids), account.riot_routing) do
              {:ok, oldest_ts} ->
                new_count = account.oldest_synced_start + length(match_ids)

                account
                |> Ash.Changeset.for_update(:update, %{
                  oldest_synced_start: new_count,
                  oldest_synced_at: oldest_ts,
                  history_fully_synced: false
                })
                |> Ash.update!()

                Logger.info(
                  "[SyncAccount] Backward pass done: oldest synced at #{oldest_ts} for #{tag}"
                )

                :ok

              {:error, _} = error ->
                error
            end

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

  defp backward_params(%{oldest_synced_at: nil}), do: [start: 0, count: @backward_page_size]

  defp backward_params(%{oldest_synced_at: oldest_synced_at}) do
    [endTime: DateTime.to_unix(oldest_synced_at, :second) - 1, count: @backward_page_size]
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
    # Optimization: check if we already have this match in the DB before calling Riot API.
    # Note: This means if match data changes on Riot side, we won't see it, 
    # but for LoL matches, the info is immutable after the game ends.
    case Receipts.Repo.get_by(Receipts.LoL.Match, riot_match_id: match_id) do
      nil ->
        case @riot_client.get_match(match_id, account.riot_routing) do
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
            Logger.warning(
              "[SyncAccount] Rate limited fetching #{match_id} for #{tag}, snoozing 65s"
            )

            {:snooze, 65}

          {:error, reason} ->
            Logger.error(
              "[SyncAccount] Failed to fetch #{match_id} for #{tag}: #{inspect(reason)}"
            )

            {:error, {match_id, reason}}
        end

      match ->
        # We already have the match. We should still ensure the participant is recorded for THIS account.
        # Let's check for the participant specifically.
        case Receipts.Repo.get_by(Receipts.LoL.MatchParticipant,
               account_id: account.id,
               match_id: match.id
             ) do
          nil ->
            # We have the match but not the participant for this account.
            # This happens if multiple tracked accounts were in the same match.
            # We need to fetch the match data once to get this participant's info.
            fetch_and_upsert_match(match_id, account, champion_map, tag)

          _participant ->
            Logger.debug("[SyncAccount] Already have #{match_id} for #{tag}, skipping")
            :ok
        end
    end
  end

  defp fetch_and_upsert_match(match_id, account, champion_map, _tag) do
    case @riot_client.get_match(match_id, account.riot_routing) do
      {:ok, match_data} ->
        info = match_data["info"]

        case find_participant(info["participants"], account.riot_puuid) do
          nil ->
            :ok

          participant ->
            upsert_match_and_participant(match_id, info, participant, account, champion_map)
        end

      {:error, :not_found} ->
        Logger.warning("[SyncAccount] #{match_id} not found in Riot API, skipping")
        :ok

      {:error, :rate_limited} ->
        Logger.warning(
          "[SyncAccount] Rate limited fetching #{match_id} for #{account.riot_game_name}, snoozing 65s"
        )

        {:snooze, 65}

      {:error, reason} ->
        Logger.error("[SyncAccount] Failed to fetch #{match_id}: #{inspect(reason)}")
        {:error, {match_id, reason}}
    end
  end

  defp find_participant(participants, puuid) do
    Enum.find(participants, fn p -> p["puuid"] == puuid end)
  end

  defp backfill_stored_matches(account, champion_map, tag) do
    case Receipts.LoL.StoredMatchParticipantBackfill.backfill_account(account, champion_map) do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Logger.info("[SyncAccount] Backfilled #{count} stored match participant(s) for #{tag}")
        :ok
    end
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

    case resolve_champion(champion_map, champion_riot_id, match_id) do
      nil ->
        Logger.warning(
          "[SyncAccount] Champion ID #{champion_riot_id} not in local map for #{match_id} after Data Dragon refresh, skipping participant"
        )

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
          raw_participant: participant,
          game_datetime: game_datetime,
          queue_type: Receipts.LoL.Queue.from_id(queue_id)
        })
        |> Ash.create!()

        Logger.debug(
          "[SyncAccount] Upserted #{match_id} (#{champion.name}) for #{account.riot_game_name}##{account.riot_tag_line}"
        )

        :ok
    end
  end

  defp load_champion_map do
    Receipts.LoL.Champion
    |> Ash.read!()
    |> Map.new(&{&1.riot_id, &1})
  end

  defp resolve_champion(champion_map, champion_riot_id, match_id) do
    case Map.get(champion_map, champion_riot_id) do
      nil -> resolve_missing_champion(champion_riot_id, match_id)
      champion -> champion
    end
  end

  defp resolve_missing_champion(champion_riot_id, match_id) do
    case Process.get(@refreshed_champion_map_key) do
      nil -> refresh_champion_map(champion_riot_id, match_id)
      champion_map -> Map.get(champion_map, champion_riot_id)
    end
  end

  defp refresh_champion_map(champion_riot_id, match_id) do
    Logger.info(
      "[SyncAccount] Champion ID #{champion_riot_id} not in local map for #{match_id}, refreshing Data Dragon"
    )

    case @data_dragon.sync_champions() do
      {:ok, _count} ->
        champion_map = load_champion_map()
        Process.put(@refreshed_champion_map_key, champion_map)
        Map.get(champion_map, champion_riot_id)

      {:error, reason} ->
        Logger.warning(
          "[SyncAccount] Data Dragon refresh failed while resolving champion ID #{champion_riot_id}: #{inspect(reason)}"
        )

        Process.put(@refreshed_champion_map_key, %{})
        nil
    end
  end
end
