defmodule Receipts.LoL.MatchParticipant do
  use Ash.Resource,
    domain: Receipts.LoL,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "lol_match_participants"
    repo Receipts.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :kills, :integer, public?: true
    attribute :deaths, :integer, public?: true
    attribute :assists, :integer, public?: true
    attribute :win, :boolean, public?: true
    attribute :cs, :integer, public?: true
    attribute :damage_dealt, :integer, public?: true
    attribute :vision_score, :integer, public?: true
    attribute :position, :string, public?: true

    attribute :items, {:array, :integer} do
      default []
      public? true
    end

    # Full participant blob from Riot API for ad-hoc access and AI context
    attribute :raw_participant, :map do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_account_match, [:account_id, :match_id]
  end

  relationships do
    belongs_to :match, Receipts.LoL.Match do
      allow_nil? false
      public? true
    end

    belongs_to :account, Receipts.LoL.Account do
      allow_nil? false
      public? true
    end

    belongs_to :champion, Receipts.LoL.Champion do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy,
              create: [:kills, :deaths, :assists, :win, :cs, :damage_dealt,
                       :vision_score, :position, :items, :raw_participant],
              update: []]
  end
end
