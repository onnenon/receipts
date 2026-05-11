defmodule Receipts.AIClientStub do
  @moduledoc false

  def generate_structured(_prompt, _schema, _opts \\ []) do
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
