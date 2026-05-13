defmodule Receipts.LoL.MatchParticipant do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_match_participants")
    repo(Receipts.Repo)

    custom_indexes do
      # Core receipts query: player's stats on a champion
      index([:account_id, :champion_id])
      # Position-filtered receipts: player's stats on a champion at a specific position
      index([:account_id, :champion_id, :position])
      # Position-filtered roster: player's stats at a position across all champions
      index([:account_id, :position])
      # "Playing with" join: find all participants in a match on a given team
      index([:match_id, :team_id])
      # Shared receipts: load known players' rows from the common match set
      index([:match_id, :account_id])
      # Recent-games query: latest N games for an account sorted by time
      index([:account_id, :game_datetime])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:kills, :integer, public?: true)
    attribute(:deaths, :integer, public?: true)
    attribute(:assists, :integer, public?: true)
    attribute(:win, :boolean, public?: true)
    attribute(:cs, :integer, public?: true)
    attribute(:damage_dealt, :integer, public?: true)
    attribute(:vision_score, :integer, public?: true)
    attribute(:position, :string, public?: true)
    attribute(:team_id, :integer, public?: true)
    attribute(:is_remake, :boolean, default: false, allow_nil?: false, public?: true)

    # Denormalized from Match for filter/sort performance (no JOIN needed)
    attribute(:game_datetime, :utc_datetime_usec, public?: true)
    attribute(:queue_type, :string, public?: true)

    attribute :items, {:array, :integer} do
      default([])
      public?(true)
    end

    # Full participant blob from Riot API for ad-hoc access and AI context
    attribute :raw_participant, :map do
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_account_match, [:account_id, :match_id])
  end

  relationships do
    belongs_to :match, Receipts.LoL.Match do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :account, Receipts.LoL.Account do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :champion, Receipts.LoL.Champion do
      allow_nil?(false)
      public?(true)
    end
  end

  actions do
    defaults([
      :read,
      :destroy,
      create: [
        :kills,
        :deaths,
        :assists,
        :win,
        :cs,
        :damage_dealt,
        :vision_score,
        :position,
        :items,
        :raw_participant
      ],
      update: []
    ])

    create :sync do
      # FK attributes from belongs_to are settable directly
      accept([
        :match_id,
        :account_id,
        :champion_id,
        :kills,
        :deaths,
        :assists,
        :win,
        :cs,
        :damage_dealt,
        :vision_score,
        :position,
        :team_id,
        :is_remake,
        :items,
        :raw_participant,
        :game_datetime,
        :queue_type
      ])

      upsert?(true)
      upsert_identity(:unique_account_match)

      upsert_fields([
        :kills,
        :deaths,
        :assists,
        :win,
        :cs,
        :damage_dealt,
        :vision_score,
        :position,
        :team_id,
        :is_remake,
        :items,
        :raw_participant,
        :game_datetime,
        :queue_type
      ])
    end
  end
end
