defmodule Receipts.AIClientStub do
  @moduledoc false

  def generate_structured(prompt, _schema, _opts \\ []) do
    cond do
      prompt |> String.downcase() |> String.contains?("run it down") ->
        {:ok,
         %{
           "verdict" => "Probably not a felony, but keep wards nearby.",
           "summary" =>
             "Koozie has no Ahri jungle games in the sample, so this is less receipt and more weather report. His mid games are stable enough to avoid full feed mode.",
           "carry_score" => 42,
           "confidence" => "low",
           "risk_label" => "Suspicious lock-in",
           "evidence" => [
             "No exact Ahri jungle games are on record.",
             "Recent games show enough KDA to avoid calling it doomed."
           ],
           "similar_champ_notes" => [
             "Same-position champions are a weaker proxy, but they keep this from being pure vibes."
           ],
           "advice" => ["Let him cook, but maybe do not path like this is a Challenger vod."],
           "caveats" => ["Zero exact champion-position games lowers confidence."]
         }}

      String.contains?(prompt, "game analysis") ->
        {:ok,
         %{
           "summary" =>
             "Koozie and Kupo have enough fight presence to win scrappy games, but the receipts turn ugly when mid pressure drops and deaths pile up.",
           "confidence" => "medium",
           "went_well" => [
             %{
               "title" => "Kupo keeps fights playable",
               "details" =>
                 "His recent stat lines show strong assist totals even when the group loses.",
               "evidence" => ["Support loss: 2/3/18", "High assist games keep late fights close"],
               "evidence_strength" => "medium"
             }
           ],
           "went_poorly" => [
             %{
               "title" => "Mid pressure falls off in losses",
               "details" =>
                 "Koozie's recent loss stat lines show low damage and too many deaths.",
               "evidence" => ["Loss on Ahri: 1/7/4 with 8k damage", "Shared loss sample is small"],
               "evidence_strength" => "high"
             }
           ],
           "receipts" => [
             %{
               "label" => "Ugliest Mid Loss",
               "player_name" => "Koozie",
               "champion" => "Ahri",
               "statline" => "1/7/4",
               "result" => "Loss",
               "takeaway" =>
                 "The damage never came online, so the group had no reliable mid-game threat."
             }
           ],
           "player_readouts" => [
             %{
               "player_id" => "player-a",
               "player_name" => "Koozie",
               "good" => "He can stabilize games when his lane does not collapse early.",
               "bad" => "He is not pulling enough weight in losing games.",
               "receipt" => "Ahri loss: 1/7/4 with 8k damage.",
               "trend" => "struggling",
               "evidence" => ["Recent shared losses average 1.0 KDA"]
             },
             %{
               "player_id" => "player-b",
               "player_name" => "Kupo",
               "good" => "He is carrying hard relative to the rest of the group.",
               "bad" => "The support impact still has to survive messy mid-game fights.",
               "receipt" => "Support loss: 2/3/18.",
               "trend" => "carrying",
               "evidence" => ["Recent losses still include high assist support games"]
             }
           ],
           "run_it_back" => ["Put Koozie on lower-death mids until his recent form recovers."],
           "caveats" => ["Shared loss sample is limited."]
         }}

      true ->
        comp_suggestion()
    end
  end

  defp comp_suggestion do
    {:ok,
     %{
       "summary" =>
         "Koozie should play mid while Kupo covers utility because she is reliable there.",
       "confidence" => "medium",
       "recommended_lineup" => [
         %{
           "player_id" => "player-a",
           "player_name" => "Koozie",
           "position" => "MIDDLE",
           "position_label" => "Mid",
           "champions" => ["Ahri"],
           "reason" => "Best shared-game sample is in mid.",
           "evidence" => [
             "Recent non-shared games: Jungle (14 games, 64.3% win rate)",
             "Recent non-shared games: Jax (2 games, 100% win rate, low sample size)",
             "recent_non_shared_positions.MIDDLE: 24 games, 58.3% win rate",
             "recent_non_shared_top_champions.Akshan: 14 games, 71.4% win rate (MIDDLE)"
           ]
         },
         %{
           "player_id" => "player-b",
           "player_name" => "Kupo",
           "position" => "UTILITY",
           "position_label" => "Utility",
           "champions" => ["Lulu"],
           "reason" => "Her recent utility games add useful context.",
           "evidence" => ["Recent non-shared support games are positive."]
         }
       ],
       "alternatives" => [
         %{
           "name" => "Safer lane setup",
           "notes" => "Keep Koozie on mid and move Kupo to utility.",
           "lineup" => [
             %{
               "player_id" => "player-a",
               "player_name" => "Koozie",
               "position" => "MIDDLE",
               "position_label" => "Mid",
               "champions" => ["Ahri"],
               "reason" => "Reliable mid option.",
               "evidence" => []
             },
             %{
               "player_id" => "player-b",
               "player_name" => "Kupo",
               "position" => "UTILITY",
               "position_label" => "Utility",
               "champions" => ["Lulu"],
               "reason" => "Reliable support option.",
               "evidence" => []
             }
           ]
         }
       ],
       "caveats" => ["Small samples should be treated carefully."]
     }}
  end
end
