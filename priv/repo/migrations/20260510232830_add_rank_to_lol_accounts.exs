defmodule Receipts.Repo.Migrations.AddRankToLolAccounts do
  use Ecto.Migration

  def change do
    alter table(:lol_accounts) do
      add :rank_tier, :string
      add :rank_division, :string
      add :rank_lp, :integer
    end
  end
end
