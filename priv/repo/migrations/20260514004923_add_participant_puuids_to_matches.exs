defmodule Receipts.Repo.Migrations.AddParticipantPuuidsToMatches do
  use Ecto.Migration

  def up do
    alter table(:lol_matches) do
      add(:participant_puuids, {:array, :text}, null: false, default: [])
    end

    execute("""
    UPDATE lol_matches
    SET participant_puuids = COALESCE(
      (
        SELECT array_agg(participant->>'puuid' ORDER BY participant->>'puuid')
        FROM jsonb_array_elements(raw_info->'participants') AS participant
        WHERE participant ? 'puuid'
      ),
      ARRAY[]::text[]
    )
    WHERE raw_info IS NOT NULL
    """)

    create(index(:lol_matches, [:participant_puuids], using: "GIN"))
  end

  def down do
    drop_if_exists(index(:lol_matches, [:participant_puuids], using: "GIN"))

    alter table(:lol_matches) do
      remove(:participant_puuids)
    end
  end
end
