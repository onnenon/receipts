defmodule Receipts.Repo.Migrations.AddPositionIndexes do
  use Ecto.Migration

  def up do
    create_if_not_exists(index(:lol_match_participants, [:account_id, :champion_id, :position]))
    create_if_not_exists(index(:lol_match_participants, [:account_id, :position]))
  end

  def down do
    drop_if_exists(index(:lol_match_participants, [:account_id, :champion_id, :position]))
    drop_if_exists(index(:lol_match_participants, [:account_id, :position]))
  end
end
