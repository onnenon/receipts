defmodule Receipts.LoL.Champion do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_champions")
    repo(Receipts.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # Numeric ID used in match data (e.g. 157 for Yasuo)
    attribute :riot_id, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    # Internal key used in Data Dragon (e.g. "Yasuo")
    attribute :key, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :image, :string do
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_riot_id, [:riot_id])
    identity(:unique_key, [:key])
  end

  relationships do
    has_many(:match_participants, Receipts.LoL.MatchParticipant)
  end

  actions do
    defaults([
      :read,
      :destroy,
      create: [:riot_id, :name, :key, :image],
      update: [:name, :key, :image]
    ])
  end
end
