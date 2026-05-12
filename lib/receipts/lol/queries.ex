defmodule Receipts.LoL.Queries do
  @moduledoc false

  import Ecto.Query

  require Ash.Query

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant, Player, Queue}
  alias Receipts.Repo

  @doc """
  Returns `{:ok, stats}` or `{:error, :champion_not_found}`.

  `champion_name` matches on display name or Data Dragon key, case-insensitive.
  Aggregates across all accounts belonging to the player.

  Options:
    - `:queue_types` — list of queue type strings to include. Defaults to `Queue.default_queues/0`.
    - `:positions` — list of position strings to include (e.g. `["TOP", "MIDDLE"]`). `[]` = all.
    - `:from_year` — integer year (inclusive lower bound on game_datetime). nil = no lower bound.
    - `:to_year` — integer year (inclusive upper bound on game_datetime). nil = no upper bound.
  """
  def receipts(player_id, champion_name, opts \\ []) when is_binary(champion_name) do
    case find_champion(champion_name) do
      nil -> {:error, :champion_not_found}
      champion -> {:ok, aggregate_stats(player_id, champion, opts)}
    end
  end

  def receipts_for_players(player_ids, champion_name, opts \\ [])
      when is_list(player_ids) and is_binary(champion_name) do
    player_ids = normalize_ids(player_ids)

    case find_champion(champion_name) do
      nil ->
        {:error, :champion_not_found}

      champion ->
        match_ids =
          Keyword.get_lazy(opts, :match_ids, fn -> comparison_match_ids(player_ids, opts) end)

        opts = Keyword.put(opts, :match_ids, match_ids)

        results =
          Enum.map(player_ids, fn player_id ->
            %{player_id: player_id, result: aggregate_stats(player_id, champion, opts)}
          end)

        {:ok, results}
    end
  end

  def common_match_ids_for_players(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)

    if length(player_ids) <= 1 do
      nil
    else
      queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
      from_year = Keyword.get(opts, :from_year)
      to_year = Keyword.get(opts, :to_year)

      MatchParticipant
      |> join(:inner, [participant], account in Account, on: account.id == participant.account_id)
      |> where([participant, account], account.player_id in ^player_ids)
      |> where([participant], participant.queue_type in ^queue_types)
      |> apply_ecto_year_filters(from_year, to_year)
      |> group_by([participant], participant.match_id)
      |> having(
        [_participant, account],
        count(account.player_id, :distinct) == ^length(player_ids)
      )
      |> select([participant], participant.match_id)
      |> Repo.all()
    end
  end

  def group_stats_for_players(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)

    match_ids =
      Keyword.get_lazy(opts, :match_ids, fn -> comparison_match_ids(player_ids, opts) end)

    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)

    account_player_ids =
      Account
      |> Ash.Query.filter(player_id in ^player_ids)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1.player_id})

    participants =
      cond do
        player_ids == [] ->
          []

        match_ids in [nil, []] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^Map.keys(account_player_ids))
          |> Ash.Query.filter(match_id in ^match_ids)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_year_filters(from_year, to_year)
          |> Ash.read!()
      end

    matches =
      participants
      |> Enum.group_by(& &1.match_id)
      |> Enum.filter(fn {_match_id, parts} ->
        parts
        |> Enum.map(&Map.get(account_player_ids, &1.account_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length() == length(player_ids)
      end)

    games_played = length(matches)

    wins =
      Enum.count(matches, fn {_match_id, parts} ->
        Enum.all?(player_ids, fn player_id ->
          Enum.any?(parts, &(Map.get(account_player_ids, &1.account_id) == player_id && &1.win))
        end)
      end)

    %{
      games_played: games_played,
      wins: wins,
      win_rate: if(games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0)
    }
  end

  def player_home_stats(players) do
    player_ids = Enum.map(players, & &1.id)

    accounts =
      Account
      |> Ash.Query.filter(player_id in ^player_ids)
      |> Ash.read!()

    accounts_by_player = Enum.group_by(accounts, & &1.player_id)
    totals_by_player = player_home_totals(player_ids)
    top_champions_by_player = player_home_top_champions(player_ids)

    Map.new(player_ids, fn player_id ->
      totals = Map.get(totals_by_player, player_id, %{total_games: 0, total_wins: 0})
      total_games = totals.total_games
      total_wins = totals.total_wins

      overall_win_rate =
        if total_games > 0, do: Float.round(total_wins / total_games * 100, 1), else: 0.0

      player_accounts = Map.get(accounts_by_player, player_id, [])

      {player_id,
       %{
         top_champion: Map.get(top_champions_by_player, player_id),
         total_games: total_games,
         total_wins: total_wins,
         overall_win_rate: overall_win_rate,
         best_rank: best_rank_for_accounts(player_accounts)
       }}
    end)
  end

  defp player_home_totals([]), do: %{}

  defp player_home_totals(player_ids) do
    MatchParticipant
    |> join(:inner, [participant], account in Account, on: account.id == participant.account_id)
    |> where([_participant, account], account.player_id in ^player_ids)
    |> group_by([_participant, account], account.player_id)
    |> select([participant, account], %{
      player_id: account.player_id,
      total_games: count(participant.id),
      total_wins: fragment("sum(CASE WHEN ? THEN 1 ELSE 0 END)", participant.win)
    })
    |> Repo.all()
    |> Map.new(fn row ->
      {row.player_id, %{total_games: row.total_games, total_wins: row.total_wins || 0}}
    end)
  end

  defp player_home_top_champions([]), do: %{}

  defp player_home_top_champions(player_ids) do
    MatchParticipant
    |> join(:inner, [participant], account in Account, on: account.id == participant.account_id)
    |> join(:inner, [participant, _account], champion in Champion,
      on: champion.id == participant.champion_id
    )
    |> where([_participant, account], account.player_id in ^player_ids)
    |> group_by([_participant, account, champion], [account.player_id, champion.id])
    |> select([participant, account, champion], %{
      player_id: account.player_id,
      champion: champion,
      games_played: count(participant.id),
      wins: fragment("sum(CASE WHEN ? THEN 1 ELSE 0 END)", participant.win)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      games_played = row.games_played
      wins = row.wins || 0

      %{
        player_id: row.player_id,
        champion: row.champion,
        games_played: games_played,
        wins: wins,
        win_rate: if(games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0)
      }
    end)
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, summaries} ->
      top =
        summaries
        |> Enum.sort_by(&{-&1.games_played, &1.champion.name})
        |> List.first()

      {player_id, top}
    end)
  end

  @tier_order ~w(IRON BRONZE SILVER GOLD PLATINUM EMERALD DIAMOND MASTER GRANDMASTER CHALLENGER)

  defp best_rank_for_accounts(accounts) do
    ranked = Enum.filter(accounts, & &1.rank_tier)

    if ranked == [] do
      nil
    else
      best =
        Enum.max_by(ranked, fn a ->
          Enum.find_index(@tier_order, &(&1 == a.rank_tier)) || -1
        end)

      %{tier: best.rank_tier, division: best.rank_division, lp: best.rank_lp}
    end
  end

  def player_top_champions(players) do
    player_ids = Enum.map(players, & &1.id)

    accounts =
      Account
      |> Ash.Query.filter(player_id in ^player_ids)
      |> Ash.read!()

    account_player_ids = Map.new(accounts, &{&1.id, &1.player_id})
    account_ids = Map.keys(account_player_ids)

    participants =
      if account_ids == [] do
        []
      else
        MatchParticipant
        |> Ash.Query.filter(account_id in ^account_ids)
        |> Ash.Query.load(:champion)
        |> Ash.read!()
      end

    participants
    |> Enum.group_by(fn participant ->
      {Map.fetch!(account_player_ids, participant.account_id), participant.champion_id}
    end)
    |> Enum.map(fn {{player_id, _champion_id}, champion_participants} ->
      games_played = length(champion_participants)
      wins = Enum.count(champion_participants, & &1.win)
      win_rate = if games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0
      champion = champion_participants |> List.first() |> Map.fetch!(:champion)

      %{
        player_id: player_id,
        champion: champion,
        games_played: games_played,
        wins: wins,
        win_rate: win_rate
      }
    end)
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, summaries} ->
      top =
        summaries
        |> Enum.sort_by(&{-&1.games_played, &1.champion.name})
        |> List.first()

      {player_id, top}
    end)
  end

  def position_breakdown_for_player(player_id, opts \\ []) do
    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)
    match_ids = Keyword.get(opts, :match_ids)

    account_ids = account_ids_for_player(player_id)

    participants =
      cond do
        account_ids == [] ->
          []

        match_ids == [] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^account_ids)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_match_filter(match_ids)
          |> apply_year_filters(from_year, to_year)
          |> Ash.read!()
      end

    participants
    |> Enum.reject(&is_nil(&1.position))
    |> Enum.group_by(& &1.position)
    |> Enum.map(fn {pos, parts} ->
      g = length(parts)
      w = Enum.count(parts, & &1.win)
      wr = if g > 0, do: Float.round(w / g * 100, 1), else: 0.0
      %{position: pos, games: g, wins: w, win_rate: wr}
    end)
    |> Enum.sort_by(fn %{games: g} -> -g end)
  end

  def top_champions_for_player(player_id, opts \\ []) do
    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)
    positions = Keyword.get(opts, :positions, [])
    match_ids = Keyword.get(opts, :match_ids)

    account_ids = account_ids_for_player(player_id)

    participants =
      cond do
        account_ids == [] ->
          []

        match_ids == [] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^account_ids)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_match_filter(match_ids)
          |> apply_year_filters(from_year, to_year)
          |> apply_position_filter(positions)
          |> Ash.Query.load(:champion)
          |> Ash.read!()
      end

    summarize_champion_participants(participants)
  end

  def top_champions_by_player(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)

    Map.new(player_ids, fn player_id ->
      {player_id, top_champions_for_player(player_id, opts)}
    end)
  end

  defp summarize_champion_participants(participants) do
    avg = fn parts, field ->
      n = length(parts)

      if n > 0,
        do: Float.round(Enum.sum(Enum.map(parts, &(Map.get(&1, field) || 0))) / n, 1),
        else: 0.0
    end

    participants
    |> Enum.group_by(& &1.champion_id)
    |> Enum.map(fn {_champion_id, parts} ->
      champion = hd(parts).champion
      games_played = length(parts)
      wins = Enum.count(parts, & &1.win)
      win_rate = if games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0
      avg_kills = avg.(parts, :kills)
      avg_deaths = avg.(parts, :deaths)
      avg_assists = avg.(parts, :assists)

      kda_ratio =
        if avg_deaths > 0,
          do: Float.round((avg_kills + avg_assists) / avg_deaths, 2),
          else: Float.round((avg_kills + avg_assists) / 1.0, 2)

      %{
        champion: champion,
        games_played: games_played,
        wins: wins,
        win_rate: win_rate,
        avg_kills: avg_kills,
        avg_deaths: avg_deaths,
        avg_assists: avg_assists,
        kda_ratio: kda_ratio
      }
    end)
    |> Enum.sort_by(fn %{games_played: g, champion: c} -> {-g, c.name} end)
  end

  def top_champions_for_players(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)
    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)
    positions = Keyword.get(opts, :positions, [])

    match_ids =
      Keyword.get_lazy(opts, :match_ids, fn -> comparison_match_ids(player_ids, opts) end)

    account_ids =
      Account
      |> Ash.Query.filter(player_id in ^player_ids)
      |> Ash.read!()
      |> Enum.map(& &1.id)

    participants =
      cond do
        account_ids == [] ->
          []

        match_ids == [] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^account_ids)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_match_filter(match_ids)
          |> apply_year_filters(from_year, to_year)
          |> apply_position_filter(positions)
          |> Ash.Query.load(:champion)
          |> Ash.read!()
      end

    avg = fn parts, field ->
      n = length(parts)

      if n > 0,
        do: Float.round(Enum.sum(Enum.map(parts, &(Map.get(&1, field) || 0))) / n, 1),
        else: 0.0
    end

    participants
    |> Enum.group_by(& &1.champion_id)
    |> Enum.map(fn {_champion_id, parts} ->
      champion = hd(parts).champion
      games_played = length(parts)
      wins = Enum.count(parts, & &1.win)
      win_rate = if games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0
      avg_kills = avg.(parts, :kills)
      avg_deaths = avg.(parts, :deaths)
      avg_assists = avg.(parts, :assists)

      kda_ratio =
        if avg_deaths > 0,
          do: Float.round((avg_kills + avg_assists) / avg_deaths, 2),
          else: Float.round((avg_kills + avg_assists) / 1.0, 2)

      %{
        champion: champion,
        games_played: games_played,
        wins: wins,
        win_rate: win_rate,
        avg_kills: avg_kills,
        avg_deaths: avg_deaths,
        avg_assists: avg_assists,
        kda_ratio: kda_ratio
      }
    end)
    |> Enum.sort_by(fn %{games_played: g, champion: c} -> {-g, c.name} end)
  end

  def comp_suggestion_context_for_players(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)

    cond do
      length(player_ids) < 2 ->
        {:error, :not_enough_players}

      true ->
        queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
        from_year = Keyword.get(opts, :from_year)
        to_year = Keyword.get(opts, :to_year)

        players = load_players_in_order(player_ids)

        if length(players) < 2 do
          {:error, :not_enough_players}
        else
          loaded_player_ids = Enum.map(players, & &1.id)

          shared_match_ids =
            Keyword.get_lazy(opts, :match_ids, fn ->
              common_match_ids_for_players(loaded_player_ids,
                queue_types: queue_types,
                from_year: from_year,
                to_year: to_year
              )
            end)

          player_contexts =
            Enum.map(players, fn player ->
              shared_participants =
                player_participants(player.id,
                  queue_types: queue_types,
                  from_year: from_year,
                  to_year: to_year,
                  match_ids: shared_match_ids,
                  load: [:champion]
                )

              recent_context_participants =
                player_recent_context_participants(player.id,
                  queue_types: queue_types,
                  from_year: from_year,
                  to_year: to_year,
                  exclude_match_ids: shared_match_ids,
                  limit: 40
                )

              all_participants =
                player_participants(player.id,
                  queue_types: queue_types,
                  from_year: from_year,
                  to_year: to_year,
                  load: [:champion]
                )

              %{
                id: player.id,
                name: player.name,
                accounts: Enum.map(player.accounts, &account_context/1),
                all_games: length(all_participants),
                shared_games: length(shared_participants),
                shared_positions: summarize_positions(shared_participants),
                recent_non_shared_positions: summarize_positions(recent_context_participants),
                overall_positions: summarize_positions(all_participants),
                shared_top_champions:
                  shared_participants
                  |> summarize_champion_participants()
                  |> serialize_champion_summaries(8),
                recent_non_shared_top_champions:
                  recent_context_participants
                  |> summarize_champion_participants()
                  |> serialize_champion_summaries(8),
                overall_top_champions:
                  all_participants
                  |> summarize_champion_participants()
                  |> serialize_champion_summaries(10)
              }
            end)

          {:ok,
           %{
             filters: %{
               queues: queue_types,
               from_year: from_year,
               to_year: to_year
             },
             selected_players: Enum.map(players, &%{id: &1.id, name: &1.name}),
             shared_games: %{
               count: length(shared_match_ids || []),
               group:
                 group_stats_for_players(loaded_player_ids,
                   queue_types: queue_types,
                   from_year: from_year,
                   to_year: to_year,
                   match_ids: shared_match_ids
                 )
             },
             players: player_contexts,
             positions: [
               %{key: "TOP", label: "Top"},
               %{key: "JUNGLE", label: "Jungle"},
               %{key: "MIDDLE", label: "Mid"},
               %{key: "BOTTOM", label: "Bot"},
               %{key: "UTILITY", label: "Support"}
             ],
             notes: [
               "shared_* stats only include games containing every selected player and matching the active filters",
               "recent_non_shared_* stats exclude those shared games and are included as individual current-form context",
               "Do not treat small samples as conclusive."
             ]
           }}
        end
    end
  end

  def win_loss_analysis_context_for_players(player_ids, opts \\ []) do
    player_ids = normalize_ids(player_ids)

    cond do
      length(player_ids) < 2 ->
        {:error, :not_enough_players}

      true ->
        queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
        from_year = Keyword.get(opts, :from_year)
        to_year = Keyword.get(opts, :to_year)
        recent_match_limit = Keyword.get(opts, :recent_match_limit, 20)
        recent_player_game_limit = Keyword.get(opts, :recent_player_game_limit, 20)

        players = load_players_in_order(player_ids)

        if length(players) < 2 do
          {:error, :not_enough_players}
        else
          loaded_player_ids = Enum.map(players, & &1.id)

          shared_match_ids =
            Keyword.get_lazy(opts, :match_ids, fn ->
              common_match_ids_for_players(loaded_player_ids,
                queue_types: queue_types,
                from_year: from_year,
                to_year: to_year
              )
            end)

          player_participants =
            Map.new(players, fn player ->
              participants =
                player_participants(player.id,
                  queue_types: queue_types,
                  from_year: from_year,
                  to_year: to_year,
                  match_ids: shared_match_ids,
                  load: [:champion, match: match_summary_query()]
                )

              {player.id, participants}
            end)

          recent_shared_matches =
            player_participants
            |> Map.values()
            |> List.flatten()
            |> Enum.group_by(& &1.match_id)
            |> Enum.map(fn {_match_id, participants} ->
              match = participants |> List.first() |> Map.get(:match)

              %{
                match_id: match.id,
                riot_match_id: match.riot_match_id,
                played_at: match.game_datetime,
                queue_type: match.queue_type,
                duration_seconds: match.game_duration_seconds,
                group_win?: participants |> List.first() |> Map.get(:win),
                participants:
                  participants
                  |> Enum.map(fn participant ->
                    player = player_for_account(players, participant.account_id)
                    participant_context(participant, player)
                  end)
                  |> Enum.sort_by(& &1.player_name)
              }
            end)
            |> Enum.sort_by(& &1.played_at, {:desc, DateTime})
            |> Enum.take(recent_match_limit)

          player_contexts =
            Enum.map(players, fn player ->
              shared_participants = Map.get(player_participants, player.id, [])

              recent_individual =
                player_recent_context_participants(player.id,
                  queue_types: queue_types,
                  from_year: from_year,
                  to_year: to_year,
                  exclude_match_ids: [],
                  limit: recent_player_game_limit
                )

              loss_participants = Enum.reject(shared_participants, & &1.win)

              %{
                id: player.id,
                name: player.name,
                accounts: Enum.map(player.accounts, &account_context/1),
                shared_summary: performance_summary(shared_participants),
                shared_loss_summary: performance_summary(loss_participants),
                shared_positions: summarize_positions(shared_participants),
                recent_individual_summary: performance_summary(recent_individual),
                recent_individual_positions: summarize_positions(recent_individual),
                recent_shared_games:
                  shared_participants
                  |> Enum.sort_by(& &1.game_datetime, {:desc, DateTime})
                  |> Enum.take(recent_match_limit)
                  |> Enum.map(&participant_context(&1, player)),
                recent_individual_games:
                  recent_individual
                  |> Enum.map(&participant_context(&1, player))
              }
            end)

          {:ok,
           %{
             filters: %{
               queues: queue_types,
               from_year: from_year,
               to_year: to_year,
               recent_match_limit: recent_match_limit,
               recent_player_game_limit: recent_player_game_limit
             },
             selected_players: Enum.map(players, &%{id: &1.id, name: &1.name}),
             shared_games: %{
               count: length(shared_match_ids || []),
               group:
                 group_stats_for_players(loaded_player_ids,
                   queue_types: queue_types,
                   from_year: from_year,
                   to_year: to_year,
                   match_ids: shared_match_ids
                 ),
               recent: recent_shared_matches
             },
             players: player_contexts,
             notes: [
               "recent shared games are games containing every selected player and matching the active filters",
               "shared_loss_summary only includes shared games the selected group lost",
               "recent_individual_* stats include each player's current form across all matching games",
               "Do not treat small samples as conclusive."
             ]
           }}
        end
    end
  end

  defp load_players_in_order(player_ids) do
    players =
      Player
      |> Ash.Query.filter(id in ^player_ids)
      |> Ash.Query.load(:accounts)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})

    player_ids
    |> Enum.map(&Map.get(players, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp account_context(account) do
    %{
      game_name: account.riot_game_name,
      tag_line: account.riot_tag_line,
      region: account.riot_region,
      rank_tier: account.rank_tier,
      rank_division: account.rank_division,
      rank_lp: account.rank_lp
    }
  end

  defp player_for_account(players, account_id) do
    Enum.find(players, fn player ->
      Enum.any?(player.accounts, &(&1.id == account_id))
    end)
  end

  defp performance_summary(participants) do
    games = length(participants)
    wins = Enum.count(participants, & &1.win)

    %{
      games: games,
      wins: wins,
      losses: games - wins,
      win_rate: percentage(wins, games),
      avg_kills: avg(participants, :kills),
      avg_deaths: avg(participants, :deaths),
      avg_assists: avg(participants, :assists),
      avg_kda_ratio: kda_ratio(participants),
      avg_cs: avg(participants, :cs),
      avg_damage_dealt: avg(participants, :damage_dealt),
      avg_vision_score: avg(participants, :vision_score)
    }
  end

  defp participant_context(participant, player) do
    %{
      player_id: if(player, do: player.id, else: nil),
      player_name: if(player, do: player.name, else: "Unknown"),
      champion: participant.champion && participant.champion.name,
      position: participant.position,
      position_label: position_label(participant.position),
      win?: participant.win,
      kills: participant.kills || 0,
      deaths: participant.deaths || 0,
      assists: participant.assists || 0,
      kda_ratio: participant_kda_ratio(participant),
      cs: participant.cs || 0,
      damage_dealt: participant.damage_dealt || 0,
      vision_score: participant.vision_score || 0,
      queue_type: participant.queue_type,
      played_at: participant.game_datetime,
      duration_seconds: participant_match_duration(participant)
    }
  end

  defp participant_match_duration(%{match: %Receipts.LoL.Match{} = match}),
    do: match.game_duration_seconds

  defp participant_match_duration(_participant), do: nil

  defp player_participants(player_id, opts) do
    queue_types = Keyword.fetch!(opts, :queue_types)
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)
    match_ids = Keyword.get(opts, :match_ids)
    load = Keyword.get(opts, :load, [])
    account_ids = account_ids_for_player(player_id)

    cond do
      account_ids == [] ->
        []

      match_ids == [] ->
        []

      true ->
        MatchParticipant
        |> Ash.Query.filter(account_id in ^account_ids)
        |> Ash.Query.filter(queue_type in ^queue_types)
        |> apply_match_filter(match_ids)
        |> apply_year_filters(from_year, to_year)
        |> maybe_load(load)
        |> Ash.read!()
    end
  end

  defp player_recent_context_participants(player_id, opts) do
    queue_types = Keyword.fetch!(opts, :queue_types)
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)
    exclude_match_ids = Keyword.get(opts, :exclude_match_ids) || []
    limit = Keyword.get(opts, :limit, 40)
    account_ids = account_ids_for_player(player_id)
    excluded = MapSet.new(exclude_match_ids)

    if account_ids == [] do
      []
    else
      MatchParticipant
      |> Ash.Query.filter(account_id in ^account_ids)
      |> Ash.Query.filter(queue_type in ^queue_types)
      |> apply_year_filters(from_year, to_year)
      |> Ash.Query.sort(game_datetime: :desc)
      |> Ash.Query.limit(limit * 2)
      |> Ash.Query.load(:champion)
      |> Ash.read!()
      |> Enum.reject(&MapSet.member?(excluded, &1.match_id))
      |> Enum.take(limit)
    end
  end

  defp maybe_load(query, []), do: query
  defp maybe_load(query, load), do: Ash.Query.load(query, load)

  defp match_summary_query do
    Ash.Query.select(Match, [
      :riot_match_id,
      :game_datetime,
      :game_duration_seconds,
      :queue_type
    ])
  end

  defp summarize_positions(participants) do
    participants
    |> Enum.reject(&is_nil(&1.position))
    |> Enum.group_by(& &1.position)
    |> Enum.map(fn {position, parts} ->
      games = length(parts)
      wins = Enum.count(parts, & &1.win)

      %{
        position: position,
        label: position_label(position),
        games: games,
        wins: wins,
        win_rate: percentage(wins, games),
        avg_kills: avg(parts, :kills),
        avg_deaths: avg(parts, :deaths),
        avg_assists: avg(parts, :assists),
        avg_cs: avg(parts, :cs),
        avg_damage_dealt: avg(parts, :damage_dealt),
        avg_vision_score: avg(parts, :vision_score),
        top_champions:
          parts
          |> summarize_champion_participants()
          |> serialize_champion_summaries(5)
      }
    end)
    |> Enum.sort_by(fn %{games: games, win_rate: win_rate} -> {-games, -win_rate} end)
  end

  defp serialize_champion_summaries(summaries, limit) do
    summaries
    |> Enum.take(limit)
    |> Enum.map(fn summary ->
      %{
        champion: %{
          id: summary.champion.id,
          key: summary.champion.key,
          name: summary.champion.name
        },
        games_played: summary.games_played,
        wins: summary.wins,
        win_rate: summary.win_rate,
        avg_kills: summary.avg_kills,
        avg_deaths: summary.avg_deaths,
        avg_assists: summary.avg_assists,
        kda_ratio: summary.kda_ratio
      }
    end)
  end

  defp avg(parts, field) do
    count = length(parts)

    if count > 0,
      do: Float.round(Enum.sum(Enum.map(parts, &(Map.get(&1, field) || 0))) / count, 1),
      else: 0.0
  end

  defp kda_ratio([]), do: 0.0

  defp kda_ratio(parts) do
    kills = avg(parts, :kills)
    deaths = avg(parts, :deaths)
    assists = avg(parts, :assists)

    if deaths > 0,
      do: Float.round((kills + assists) / deaths, 2),
      else: Float.round((kills + assists) / 1.0, 2)
  end

  defp participant_kda_ratio(participant) do
    kills = participant.kills || 0
    deaths = participant.deaths || 0
    assists = participant.assists || 0

    if deaths > 0,
      do: Float.round((kills + assists) / deaths, 2),
      else: Float.round((kills + assists) / 1.0, 2)
  end

  defp percentage(_wins, 0), do: 0.0
  defp percentage(wins, games), do: Float.round(wins / games * 100, 1)

  defp position_label("TOP"), do: "Top"
  defp position_label("JUNGLE"), do: "Jungle"
  defp position_label("MIDDLE"), do: "Mid"
  defp position_label("BOTTOM"), do: "Bot"
  defp position_label("UTILITY"), do: "Support"

  defp position_label(position) when is_binary(position),
    do: String.capitalize(String.downcase(position))

  defp position_label(_), do: "Unknown"

  defp find_champion(name) do
    Ash.read!(Champion)
    |> Enum.find(fn c ->
      String.downcase(c.name) == String.downcase(name) or
        String.downcase(c.key) == String.downcase(name)
    end)
  end

  defp account_ids_for_player(player_id) do
    Account
    |> Ash.Query.filter(player_id == ^player_id)
    |> Ash.read!()
    |> Enum.map(& &1.id)
  end

  defp aggregate_stats(player_id, champion, opts) do
    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year, nil)
    to_year = Keyword.get(opts, :to_year, nil)
    positions = Keyword.get(opts, :positions, [])
    match_ids = Keyword.get(opts, :match_ids)

    account_ids = account_ids_for_player(player_id)

    # Load all participants for aggregate stats — no match JOIN needed.
    all_participants =
      cond do
        account_ids == [] ->
          []

        match_ids == [] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^account_ids and champion_id == ^champion.id)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_match_filter(match_ids)
          |> apply_year_filters(from_year, to_year)
          |> apply_position_filter(positions)
          |> Ash.read!()
      end

    games_played = length(all_participants)
    wins = Enum.count(all_participants, & &1.win)
    win_rate = if games_played > 0, do: Float.round(wins / games_played * 100, 1), else: 0.0

    avg = fn field ->
      if games_played > 0 do
        total = Enum.sum(Enum.map(all_participants, &(Map.get(&1, field) || 0)))
        Float.round(total / games_played, 1)
      else
        0.0
      end
    end

    avg_kills = avg.(:kills)
    avg_deaths = avg.(:deaths)
    avg_assists = avg.(:assists)
    avg_cs = avg.(:cs)

    kda_ratio =
      if avg_deaths > 0,
        do: Float.round((avg_kills + avg_assists) / avg_deaths, 2),
        else: Float.round((avg_kills + avg_assists) / 1.0, 2)

    position_stats =
      all_participants
      |> Enum.reject(&is_nil(&1.position))
      |> Enum.group_by(& &1.position)
      |> Enum.map(fn {pos, parts} ->
        g = length(parts)
        w = Enum.count(parts, & &1.win)
        wr = if g > 0, do: Float.round(w / g * 100, 1), else: 0.0
        %{position: pos, games: g, wins: w, win_rate: wr}
      end)
      |> Enum.sort_by(fn %{games: g} -> -g end)

    # Separate query for recent games: sorted in SQL, only 20 rows, match loaded.
    recent_games =
      cond do
        account_ids == [] ->
          []

        match_ids == [] ->
          []

        true ->
          MatchParticipant
          |> Ash.Query.filter(account_id in ^account_ids and champion_id == ^champion.id)
          |> Ash.Query.filter(queue_type in ^queue_types)
          |> apply_match_filter(match_ids)
          |> apply_year_filters(from_year, to_year)
          |> apply_position_filter(positions)
          |> Ash.Query.sort(game_datetime: :desc)
          |> Ash.Query.limit(20)
          |> Ash.Query.load(match: match_summary_query())
          |> Ash.read!()
      end

    %{
      champion: champion,
      games_played: games_played,
      wins: wins,
      win_rate: win_rate,
      avg_kills: avg_kills,
      avg_deaths: avg_deaths,
      avg_assists: avg_assists,
      kda_ratio: kda_ratio,
      avg_cs: avg_cs,
      position_stats: position_stats,
      recent_games: recent_games
    }
  end

  defp apply_position_filter(query, positions) when positions in [nil, []], do: query

  defp apply_position_filter(query, positions) do
    Ash.Query.filter(query, position in ^positions)
  end

  defp apply_match_filter(query, nil), do: query

  defp apply_match_filter(query, match_ids) do
    Ash.Query.filter(query, match_id in ^match_ids)
  end

  defp apply_year_filters(query, from_year, to_year) do
    query
    |> then(fn q ->
      if from_year do
        from_dt = DateTime.new!(Date.new!(from_year, 1, 1), ~T[00:00:00], "Etc/UTC")
        Ash.Query.filter(q, game_datetime >= ^from_dt)
      else
        q
      end
    end)
    |> then(fn q ->
      if to_year do
        to_dt = DateTime.new!(Date.new!(to_year + 1, 1, 1), ~T[00:00:00], "Etc/UTC")
        Ash.Query.filter(q, game_datetime < ^to_dt)
      else
        q
      end
    end)
  end

  defp apply_ecto_year_filters(query, from_year, to_year) do
    query
    |> then(fn q ->
      if from_year do
        from_dt = DateTime.new!(Date.new!(from_year, 1, 1), ~T[00:00:00], "Etc/UTC")
        where(q, [participant], participant.game_datetime >= ^from_dt)
      else
        q
      end
    end)
    |> then(fn q ->
      if to_year do
        to_dt = DateTime.new!(Date.new!(to_year + 1, 1, 1), ~T[00:00:00], "Etc/UTC")
        where(q, [participant], participant.game_datetime < ^to_dt)
      else
        q
      end
    end)
  end

  defp comparison_match_ids([_player_id], _opts), do: nil
  defp comparison_match_ids([], _opts), do: []
  defp comparison_match_ids(player_ids, opts), do: common_match_ids_for_players(player_ids, opts)

  def available_queue_types_for_players([_single_player_id] = player_ids) do
    player_ids = normalize_ids(player_ids)

    account_ids =
      Account
      |> Ash.Query.filter(player_id in ^player_ids)
      |> Ash.read!()
      |> Enum.map(& &1.id)

    if account_ids == [] do
      MapSet.new()
    else
      from(p in MatchParticipant,
        where: p.account_id in ^account_ids and not is_nil(p.queue_type),
        select: p.queue_type,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  def available_queue_types_for_players(player_ids) do
    player_ids = normalize_ids(player_ids)
    all_queue_types = for {type, _label, _default} <- Queue.ui_queues(), do: type

    match_ids = common_match_ids_for_players(player_ids, queue_types: all_queue_types)

    if match_ids == [] do
      MapSet.new()
    else
      from(p in MatchParticipant,
        where: p.match_id in ^match_ids and not is_nil(p.queue_type),
        select: p.queue_type,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  defp normalize_ids(ids) do
    ids
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
