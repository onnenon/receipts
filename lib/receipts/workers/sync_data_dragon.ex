defmodule Receipts.Workers.SyncDataDragon do
  use Oban.Worker, queue: :data_dragon, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[SyncDataDragon] Starting champion data sync")

    case Receipts.Riot.DataDragon.sync_champions() do
      {:ok, count} ->
        Logger.info("[SyncDataDragon] Synced #{count} champions successfully")
        :ok

      {:error, reason} ->
        Logger.error("[SyncDataDragon] Sync failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
