defmodule Receipts.Repo.Migrations.AddLastSyncedAtToAccounts do
  use Ecto.Migration

  def change do
    alter table(:lol_accounts) do
      add(:last_synced_at, :utc_datetime_usec)
    end

    execute(
      """
      UPDATE lol_accounts
      SET last_synced_at = updated_at
      WHERE newest_synced_at IS NOT NULL
      """,
      """
      UPDATE lol_accounts
      SET last_synced_at = NULL
      """
    )
  end
end
