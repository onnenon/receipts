defmodule Receipts.LoL.Account do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_accounts")
    repo(Receipts.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :riot_puuid, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :riot_game_name, :string do
      public?(true)
    end

    attribute :riot_tag_line, :string do
      public?(true)
    end

    # Platform routing value: na1, euw1, kr, etc.
    attribute :riot_region, :string do
      allow_nil?(false)
      public?(true)
    end

    # Regional routing value: americas, europe, asia, sea
    attribute :riot_routing, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :newest_synced_at, :utc_datetime_usec do
      public?(true)
    end

    # Pagination index for backward history fetch
    attribute :oldest_synced_start, :integer do
      default(0)
      public?(true)
    end

    attribute :history_fully_synced, :boolean do
      default(false)
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_puuid, [:riot_puuid])
  end

  relationships do
    belongs_to :player, Receipts.LoL.Player do
      allow_nil?(false)
      public?(true)
    end

    has_many(:match_participants, Receipts.LoL.MatchParticipant)
  end

  actions do
    defaults([
      :read,
      :destroy,
      create: [
        :riot_puuid,
        :riot_game_name,
        :riot_tag_line,
        :riot_region,
        :riot_routing,
        :player_id
      ],
      update: [
        :riot_game_name,
        :riot_tag_line,
        :newest_synced_at,
        :oldest_synced_start,
        :history_fully_synced
      ]
    ])
  end
end
