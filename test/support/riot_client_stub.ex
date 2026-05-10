defmodule Receipts.RiotClientStub do
  @moduledoc false

  def reset do
    :persistent_term.put(__MODULE__, %{
      accounts_by_riot_id: nil,
      match_id_calls: [],
      match_ids: nil,
      matches: nil
    })
  end

  def put_accounts_by_riot_id(callback) when is_function(callback, 3) do
    update_state(&Map.put(&1, :accounts_by_riot_id, callback))
  end

  def put_match_ids(callback) when is_function(callback, 3) do
    update_state(&Map.put(&1, :match_ids, callback))
  end

  def put_matches(callback) when is_function(callback, 2) do
    update_state(&Map.put(&1, :matches, callback))
  end

  def match_id_calls do
    __MODULE__
    |> state()
    |> Map.fetch!(:match_id_calls)
    |> Enum.reverse()
  end

  def get_account_by_riot_id(game_name, tag_line, routing) do
    callback = Map.fetch!(state(__MODULE__), :accounts_by_riot_id)
    callback.(game_name, tag_line, routing)
  end

  def get_match_ids(puuid, routing, opts) do
    update_state(
      &Map.update!(&1, :match_id_calls, fn calls -> [{puuid, routing, opts} | calls] end)
    )

    callback = Map.fetch!(state(__MODULE__), :match_ids)
    callback.(puuid, routing, opts)
  end

  def get_match(match_id, routing) do
    callback = Map.fetch!(state(__MODULE__), :matches)
    callback.(match_id, routing)
  end

  def get_rank_by_puuid(puuid, platform) do
    case Map.get(state(__MODULE__), :rank_entries) do
      nil -> {:ok, []}
      callback -> callback.(puuid, platform)
    end
  end

  defp update_state(callback) do
    :persistent_term.put(__MODULE__, callback.(state(__MODULE__)))
  end

  defp state(key) do
    :persistent_term.get(key, %{
      accounts_by_riot_id: nil,
      match_id_calls: [],
      match_ids: nil,
      matches: nil
    })
  end
end
