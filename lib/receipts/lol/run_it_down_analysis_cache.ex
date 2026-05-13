defmodule Receipts.LoL.RunItDownAnalysisCache do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_run_it_down_analyses")
    repo(Receipts.Repo)

    custom_indexes do
      index([:cache_key, :generated_at])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :cache_key, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :player_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :champion_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :position, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :positions, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :filters, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    attribute :analysis, :map do
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
        :cache_key,
        :player_id,
        :champion_id,
        :position,
        :positions,
        :filters,
        :analysis,
        :generated_at
      ]
    ])
  end
end
