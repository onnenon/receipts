defmodule Receipts.Repo.Migrations.AddContextConfigToCompPromptLabRuns do
  use Ecto.Migration

  def change do
    alter table(:lol_comp_prompt_lab_runs) do
      add(:context_config, :map, null: false, default: %{})
    end
  end
end
