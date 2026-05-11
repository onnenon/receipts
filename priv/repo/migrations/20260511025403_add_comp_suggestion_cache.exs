defmodule Receipts.Repo.Migrations.AddCompSuggestionCache do
  use Ecto.Migration

  def change do
    create table(:lol_comp_suggestions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:cache_key, :text, null: false)
      add(:player_ids, {:array, :text}, null: false, default: [])
      add(:filters, :map, null: false, default: %{})
      add(:suggestion, :map, null: false)
      add(:generated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:lol_comp_suggestions, [:cache_key, :generated_at]))
  end
end
