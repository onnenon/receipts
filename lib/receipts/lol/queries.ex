defmodule Receipts.LoL.Queries do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{Account, Champion, MatchParticipant, Queue}

  @doc """
  Returns `{:ok, stats}` or `{:error, :champion_not_found}`.

  `champion_name` matches on display name or Data Dragon key, case-insensitive.
  Aggregates across all accounts belonging to the player.

  Options:
    - `:queue_types` — list of queue type strings to include. Defaults to `Queue.default_queues/0`.
    - `:from_year` — integer year (inclusive lower bound on game_datetime). nil = no lower bound.
    - `:to_year` — integer year (inclusive upper bound on game_datetime). nil = no upper bound.
  """
  def receipts(player_id, champion_name, opts \\ []) when is_binary(champion_name) do
    case find_champion(champion_name) do
      nil -> {:error, :champion_not_found}
      champion -> {:ok, aggregate_stats(player_id, champion, opts)}
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

  def top_champions_for_player(player_id, opts \\ []) do
    queue_types = Keyword.get(opts, :queue_types, Queue.default_queues())
    from_year = Keyword.get(opts, :from_year)
    to_year = Keyword.get(opts, :to_year)

    account_ids = account_ids_for_player(player_id)

    participants =
      if account_ids == [] do
        []
      else
        MatchParticipant
        |> Ash.Query.filter(account_id in ^account_ids)
        |> Ash.Query.filter(queue_type in ^queue_types)
        |> apply_year_filters(from_year, to_year)
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
          else: Float.round(avg_kills + avg_assists, 2)

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

    account_ids = account_ids_for_player(player_id)

    # Load all participants for aggregate stats — no match JOIN needed.
    all_participants =
      if account_ids == [] do
        []
      else
        MatchParticipant
        |> Ash.Query.filter(account_id in ^account_ids and champion_id == ^champion.id)
        |> Ash.Query.filter(queue_type in ^queue_types)
        |> apply_year_filters(from_year, to_year)
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
        else: Float.round(avg_kills + avg_assists, 2)

    # Separate query for recent games: sorted in SQL, only 5 rows, match loaded.
    recent_games =
      if account_ids == [] do
        []
      else
        MatchParticipant
        |> Ash.Query.filter(account_id in ^account_ids and champion_id == ^champion.id)
        |> Ash.Query.filter(queue_type in ^queue_types)
        |> apply_year_filters(from_year, to_year)
        |> Ash.Query.sort(game_datetime: :desc)
        |> Ash.Query.limit(5)
        |> Ash.Query.load(:match)
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
      recent_games: recent_games
    }
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
end
