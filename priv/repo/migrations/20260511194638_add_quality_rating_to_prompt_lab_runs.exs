defmodule Receipts.Repo.Migrations.AddQualityRatingToPromptLabRuns do
  use Ecto.Migration

  def change do
    alter table(:lol_comp_prompt_lab_runs) do
      add :quality_rating, :integer, null: true
    end

    alter table(:lol_win_loss_prompt_lab_runs) do
      add :quality_rating, :integer, null: true
    end
  end
end
