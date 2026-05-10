defmodule Receipts.LoL.Player do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_players")
    repo(Receipts.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :discord_id, :string do
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_discord_id, [:discord_id])
  end

  relationships do
    has_many(:accounts, Receipts.LoL.Account)
  end

  aggregates do
    first :oldest_game_date, [:accounts, :match_participants, :match], :game_datetime do
      sort(game_datetime: :asc)
    end

    first :newest_game_date, [:accounts, :match_participants, :match], :game_datetime do
      sort(game_datetime: :desc)
    end
  end

  actions do
    defaults([:read, :destroy, create: [:name, :discord_id], update: [:name, :discord_id]])
  end
end
