defmodule Receipts.Repo.Migrations.AddIndexAccountsPlayerId do
  use Ecto.Migration

  def change do
    create index(:lol_accounts, [:player_id])
  end
end
