defmodule Receipts.LoL.CompPromptLabRun do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_comp_prompt_lab_runs")
    repo(Receipts.Repo)

    custom_indexes do
      index([:group_key, :generated_at])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :group_key, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :player_ids, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :filters, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    attribute :system_instruction, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :prompt_template, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :context, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    attribute :context_config, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    attribute :temperature, :float do
      allow_nil?(false)
      public?(true)
    end

    attribute :suggestion, :map do
      allow_nil?(false)
      public?(true)
    end

    attribute :generated_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([
      :read,
      :destroy,
      create: [
        :group_key,
        :player_ids,
        :filters,
        :system_instruction,
        :prompt_template,
        :context,
        :context_config,
        :temperature,
        :suggestion,
        :generated_at
      ]
    ])
  end
end
