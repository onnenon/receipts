defmodule Receipts.Repo.Migrations.CreateWinLossPromptLabRuns do
  use Ecto.Migration

  def change do
    create table(:lol_win_loss_prompt_lab_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :group_key, :string, null: false
      add :player_ids, {:array, :string}, null: false, default: []
      add :filters, :map, null: false, default: %{}
      add :system_instruction, :text, null: false
      add :prompt_template, :text, null: false
      add :context, :map, null: false, default: %{}
      add :context_config, :map, null: false, default: %{}
      add :temperature, :float, null: false
      add :analysis, :map, null: false
      add :generated_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create index(:lol_win_loss_prompt_lab_runs, [:group_key, :generated_at])
  end
end
