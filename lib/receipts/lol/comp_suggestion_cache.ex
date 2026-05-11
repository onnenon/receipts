defmodule Receipts.LoL.CompSuggestionCache do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_comp_suggestions")
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
      create: [:cache_key, :player_ids, :filters, :suggestion, :generated_at]
    ])
  end
end
