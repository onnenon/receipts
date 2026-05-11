defmodule Receipts.Repo.Migrations.BackfillNullQueueTypeOnMatchParticipants do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE lol_match_participants mp
    SET game_datetime = m.game_datetime,
        queue_type    = m.queue_type
    FROM lol_matches m
    WHERE mp.match_id = m.id
      AND (mp.queue_type IS NULL OR mp.game_datetime IS NULL)
    """)
  end

  def down, do: :ok
end
