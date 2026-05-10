defmodule Receipts.Repo.Migrations.AddOldestSyncedAtToAccounts do
  use Ecto.Migration

  def change do
    alter table(:lol_accounts) do
      add(:oldest_synced_at, :utc_datetime_usec)
    end

    execute(
      """
      UPDATE lol_accounts
      SET history_fully_synced = false,
          oldest_synced_start = 0,
          oldest_synced_at = NULL
      """,
      """
      UPDATE lol_accounts
      SET oldest_synced_at = NULL
      """
    )
  end
end
