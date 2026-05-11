defmodule Receipts.DataDragonStub do
  @moduledoc false

  def reset do
    :persistent_term.put(__MODULE__, %{sync: fn -> {:ok, 0} end, sync_calls: 0})
  end

  def put_sync(callback) when is_function(callback, 0) do
    update_state(&Map.put(&1, :sync, callback))
  end

  def sync_calls do
    __MODULE__
    |> state()
    |> Map.fetch!(:sync_calls)
  end

  def sync_champions do
    update_state(&Map.update!(&1, :sync_calls, fn count -> count + 1 end))

    __MODULE__
    |> state()
    |> Map.fetch!(:sync)
    |> then(& &1.())
  end

  defp update_state(callback) do
    :persistent_term.put(__MODULE__, callback.(state(__MODULE__)))
  end

  defp state(key) do
    :persistent_term.get(key, %{sync: fn -> {:ok, 0} end, sync_calls: 0})
  end
end
