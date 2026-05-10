defmodule Receipts.LoL.StoredMatchParticipantBackfill do
  @moduledoc false

  import Ecto.Query

  alias Receipts.LoL.{Account, Champion, Match, MatchParticipant}
  alias Receipts.Repo

  def backfill_account(%Account{} = account, champion_map \\ nil) do
    champion_map = champion_map || load_champion_map()

    count =
      account
      |> candidate_matches()
      |> Enum.reduce(0, fn match, count ->
        case participant_for_account(match, account) do
          nil ->
            count

          participant ->
            case Map.get(champion_map, participant["championId"]) do
              nil ->
                count

              champion ->
                upsert_participant!(match, account, champion, participant)
                count + 1
            end
        end
      end)

    {:ok, count}
  end

  defp candidate_matches(account) do
    puuid_pattern = "%#{account.riot_puuid}%"

    Match
    |> join(:left, [match], participant in MatchParticipant,
      on: participant.match_id == match.id and participant.account_id == ^account.id
    )
    |> where([match, participant], is_nil(participant.id))
    |> where([match], fragment("?::text LIKE ?", match.raw_info, ^puuid_pattern))
    |> order_by([match], asc: match.game_datetime)
    |> Repo.all()
  end

  defp participant_for_account(match, account) do
    match.raw_info
    |> Map.get("participants", [])
    |> Enum.find(&(&1["puuid"] == account.riot_puuid))
  end

  defp upsert_participant!(match, account, champion, participant) do
    items = Enum.map(0..6, &(participant["item#{&1}"] || 0))
    cs = (participant["totalMinionsKilled"] || 0) + (participant["neutralMinionsKilled"] || 0)
    position = participant["teamPosition"]

    MatchParticipant
    |> Ash.Changeset.for_create(:sync, %{
      match_id: match.id,
      account_id: account.id,
      champion_id: champion.id,
      kills: participant["kills"],
      deaths: participant["deaths"],
      assists: participant["assists"],
      win: participant["win"],
      cs: cs,
      damage_dealt: participant["totalDamageDealtToChampions"],
      vision_score: participant["visionScore"],
      position: if(position == "", do: nil, else: position),
      team_id: participant["teamId"],
      items: items,
      raw_participant: participant
    })
    |> Ash.create!()
  end

  defp load_champion_map do
    Champion
    |> Ash.read!()
    |> Map.new(&{&1.riot_id, &1})
  end
end
