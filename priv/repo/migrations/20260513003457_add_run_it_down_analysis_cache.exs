defmodule Receipts.Repo.Migrations.AddRunItDownAnalysisCache do
  use Ecto.Migration

  def change do
    create table(:lol_run_it_down_analyses, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:cache_key, :text, null: false)
      add(:player_id, :text, null: false)
      add(:champion_id, :uuid, null: false)
      add(:position, :text, null: false)
      add(:filters, :map, null: false, default: %{})
      add(:analysis, :map, null: false)
      add(:generated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:lol_run_it_down_analyses, [:cache_key, :generated_at]))
  end
end
