defmodule Receipts.Repo.Migrations.AddMatchParticipantsMatchAccountIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists(index(:lol_match_participants, [:match_id, :account_id]))
  end
end
