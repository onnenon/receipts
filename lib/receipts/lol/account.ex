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

    attribute :last_synced_at, :utc_datetime_usec do
      public?(true)
    end

    # Legacy pagination count, retained for display/migration compatibility.
    attribute :oldest_synced_start, :integer do
      default(0)
      public?(true)
    end

    # Timestamp cursor for the oldest match in the contiguous history window already traversed.
    attribute :oldest_synced_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :history_fully_synced, :boolean do
      default(false)
      public?(true)
    end

    # Solo/Duo rank (falls back to Flex if unranked in Solo). Nil = unranked.
    attribute(:rank_tier, :string, public?: true)
    attribute(:rank_division, :string, public?: true)
    attribute(:rank_lp, :integer, public?: true)

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

  aggregates do
    first :oldest_game_datetime, [:match_participants, :match], :game_datetime do
      sort(game_datetime: :asc)
    end
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
        :riot_puuid,
        :riot_game_name,
        :riot_tag_line,
        :newest_synced_at,
        :last_synced_at,
        :oldest_synced_start,
        :oldest_synced_at,
        :history_fully_synced,
        :rank_tier,
        :rank_division,
        :rank_lp
      ]
    ])
  end
end
