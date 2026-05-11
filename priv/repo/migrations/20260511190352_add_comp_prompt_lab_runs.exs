defmodule Receipts.Repo.Migrations.AddCompPromptLabRuns do
  use Ecto.Migration

  def change do
    create table(:lol_comp_prompt_lab_runs, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:group_key, :text, null: false)
      add(:player_ids, {:array, :text}, null: false, default: [])
      add(:filters, :map, null: false, default: %{})
      add(:system_instruction, :text, null: false)
      add(:prompt_template, :text, null: false)
      add(:context, :map, null: false, default: %{})
      add(:temperature, :float, null: false)
      add(:suggestion, :map, null: false)
      add(:generated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:lol_comp_prompt_lab_runs, [:group_key, :generated_at]))
  end
end
