defmodule Receipts.RiotClientStub do
  @moduledoc false

  def reset do
    Process.put(__MODULE__, %{match_id_calls: [], match_ids: nil, matches: nil})
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

  defp update_state(callback) do
    Process.put(__MODULE__, callback.(state(__MODULE__)))
  end

  defp state(key) do
    Process.get(key) || %{match_id_calls: [], match_ids: nil, matches: nil}
  end
end
