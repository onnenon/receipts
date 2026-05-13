defmodule Receipts.Repo.Migrations.AddIsRemakeToMatchParticipants do
  use Ecto.Migration

  def up do
    alter table(:lol_match_participants) do
      add(:is_remake, :boolean, null: false, default: false)
    end

    execute("""
    UPDATE lol_match_participants
    SET is_remake = true
    WHERE raw_participant->>'gameEndedInEarlySurrender' = 'true'
    """)
  end

  def down do
    alter table(:lol_match_participants) do
      remove(:is_remake)
    end
  end
end
