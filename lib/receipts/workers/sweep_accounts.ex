defmodule Receipts.Workers.SweepAccounts do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  @stale_minutes Application.compile_env(:receipts, :sync_stale_minutes, 30)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    stale_cutoff = DateTime.add(DateTime.utc_now(), -@stale_minutes * 60, :second)

    accounts =
      Receipts.LoL.Account
      |> Ash.Query.filter(is_nil(newest_synced_at) or newest_synced_at < ^stale_cutoff)
      |> Ash.read!()

    for account <- accounts do
      %{account_id: account.id}
      |> Receipts.Workers.SyncAccount.new()
      |> Oban.insert!()
    end

    :ok
  end
end
