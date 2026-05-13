defmodule Receipts.Repo.Migrations.AddPositionsToRunItDownAnalysisCache do
  use Ecto.Migration

  def change do
    alter table(:lol_run_it_down_analyses) do
      add(:positions, {:array, :text}, null: false, default: [])
    end

    execute(
      "UPDATE lol_run_it_down_analyses SET positions = ARRAY[position] WHERE position IS NOT NULL AND positions = '{}'",
      ""
    )
  end
end
