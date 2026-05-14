defmodule Receipts.LoL.Match do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lol_matches")
    repo(Receipts.Repo)

    custom_indexes do
      index([:game_datetime])
      index([:queue_type])
      index([:participant_puuids], using: "GIN")
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :riot_match_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :game_datetime, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute :game_duration_seconds, :integer do
      public?(true)
    end

    attribute :queue_id, :integer do
      public?(true)
    end

    attribute :queue_type, :string do
      public?(true)
    end

    attribute :participant_puuids, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    # Full match info blob from Riot API for ad-hoc access and AI context
    attribute :raw_info, :map do
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_match_id, [:riot_match_id])
  end

  relationships do
    has_many(:match_participants, Receipts.LoL.MatchParticipant)
  end

  actions do
    defaults([
      :read,
      :destroy,
      create: [
        :riot_match_id,
        :game_datetime,
        :game_duration_seconds,
        :queue_id,
        :queue_type,
        :participant_puuids,
        :raw_info
      ],
      update: []
    ])

    create :sync do
      accept([
        :riot_match_id,
        :game_datetime,
        :game_duration_seconds,
        :queue_id,
        :queue_type,
        :participant_puuids,
        :raw_info
      ])

      upsert?(true)
      upsert_identity(:unique_match_id)
      upsert_fields([:queue_id, :queue_type, :participant_puuids, :raw_info])
    end
  end
end
