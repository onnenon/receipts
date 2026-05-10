defmodule Receipts.Repo.Migrations.DenormalizeGameDatetimeQueueTypeOntoMatchParticipants do
  use Ecto.Migration

  def change do
    alter table(:lol_match_participants) do
      add :game_datetime, :utc_datetime_usec
      add :queue_type, :string
    end

    execute(
      """
      UPDATE lol_match_participants mp
      SET game_datetime = m.game_datetime,
          queue_type    = m.queue_type
      FROM lol_matches m
      WHERE mp.match_id = m.id
      """,
      ""
    )

    create index(:lol_match_participants, [:account_id, :game_datetime])
  end
end
