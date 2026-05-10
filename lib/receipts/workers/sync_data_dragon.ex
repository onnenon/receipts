defmodule Receipts.Workers.SyncDataDragon do
  use Oban.Worker, queue: :data_dragon, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Receipts.Riot.DataDragon.sync_champions() do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
