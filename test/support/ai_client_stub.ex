defmodule Receipts.AIClientStub do
  @moduledoc false

  def generate_structured(prompt, _schema, _opts \\ []) do
    if String.contains?(prompt, "game analysis") do
      {:ok,
       %{
         "summary" =>
           "Recent games are mostly decided by low damage mid games, but Kupo is carrying hard when fights go long.",
         "confidence" => "medium",
         "loss_causes" => [
           %{
             "title" => "Mid pressure falls off in losses",
             "details" => "Koozie's recent loss stat lines show low damage and too many deaths.",
             "evidence" => ["Loss on Ahri: 1/7/4 with 8k damage", "Shared loss sample is small"],
             "severity" => "high"
           }
         ],
         "player_readouts" => [
           %{
             "player_id" => "player-a",
             "player_name" => "Koozie",
             "verdict" => "He is not pulling enough weight in losing games.",
             "trend" => "struggling",
             "evidence" => ["Recent shared losses average 1.0 KDA"]
           },
           %{
             "player_id" => "player-b",
             "player_name" => "Kupo",
             "verdict" => "He is carrying hard relative to the rest of the group.",
             "trend" => "carrying",
             "evidence" => ["Recent losses still include high assist support games"]
           }
         ],
         "carry_highlights" => [
           %{
             "title" => "Kupo keeps fights playable",
             "details" => "His recent stat lines show strong assist totals even in losses.",
             "evidence" => ["Support loss: 2/3/18"],
             "severity" => "medium"
           }
         ],
         "recommendations" => ["Put Koozie on lower-death mids until his recent form recovers."],
         "caveats" => ["Shared loss sample is limited."]
       }}
    else
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
