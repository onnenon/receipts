defmodule Receipts.AIClientStub do
  @moduledoc false

  def generate_structured(_prompt, _schema, _opts \\ []) do
    {:ok,
     %{
       "summary" => "Koozie should play mid while Kupo covers support.",
       "confidence" => "medium",
       "recommended_lineup" => [
         %{
           "player_id" => "player-a",
           "player_name" => "Koozie",
           "position" => "MIDDLE",
           "position_label" => "Mid",
           "champions" => ["Ahri"],
           "reason" => "Best shared-game sample is in mid.",
           "evidence" => ["Shared mid games are the strongest signal."]
         },
         %{
           "player_id" => "player-b",
           "player_name" => "Kupo",
           "position" => "UTILITY",
           "position_label" => "Support",
           "champions" => ["Lulu"],
           "reason" => "Recent support games add useful context.",
           "evidence" => ["Recent non-shared support games are positive."]
         }
       ],
       "alternatives" => [
         %{
           "name" => "Safer lane setup",
           "notes" => "Keep Koozie on mid and move Kupo to utility.",
           "lineup" => []
         }
       ],
       "caveats" => ["Small samples should be treated carefully."]
     }}
  end
end
