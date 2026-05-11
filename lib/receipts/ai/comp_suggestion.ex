defmodule Receipts.AI.CompSuggestion do
  @moduledoc false

  alias Receipts.LoL.Queries

  @positions ~w(TOP JUNGLE MIDDLE BOTTOM UTILITY)

  def suggest(player_ids, opts \\ []) do
    with {:ok, context} <- Queries.comp_suggestion_context_for_players(player_ids, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  defp ai_client do
    Application.get_env(:receipts, :ai_client, Receipts.AI.Gemini)
  end

  defp ai_opts do
    [
      system_instruction: """
      You are helping a private League of Legends friend group choose roles and champions.
      Use only the supplied JSON. Recommend one primary position per player.
      Prefer evidence from shared games, then recent non-shared games, then overall games.
      Be explicit about low sample sizes. Do not invent player history or champion stats.
      Write user-facing prose. Never include raw JSON path names, snake_case keys, or dotted
      references like recent_non_shared_positions.MIDDLE in the response.
      Each alternative must include a complete lineup with one slot for every selected player.
      """,
      temperature: 0.25,
      connect_timeout: 10_000,
      receive_timeout: 90_000
    ]
  end

  defp prompt(context) do
    """
    Generate a comp suggestion for this selected group.

    Return JSON matching the schema. Use player_id values exactly as provided.
    Valid positions are TOP, JUNGLE, MIDDLE, BOTTOM, UTILITY.

    Context:
    #{Jason.encode!(context)}
    """
  end

  defp response_schema do
    %{
      type: "OBJECT",
      properties: %{
        summary: %{type: "STRING"},
        confidence: %{type: "STRING", enum: ["low", "medium", "high"]},
        recommended_lineup: %{
          type: "ARRAY",
          items: lineup_slot_schema()
        },
        alternatives: %{
          type: "ARRAY",
          items: %{
            type: "OBJECT",
            properties: %{
              name: %{type: "STRING"},
              notes: %{type: "STRING"},
              lineup: %{type: "ARRAY", items: lineup_slot_schema()}
            },
            required: ["name", "notes", "lineup"],
            propertyOrdering: ["name", "notes", "lineup"]
          }
        },
        caveats: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: ["summary", "confidence", "recommended_lineup", "alternatives", "caveats"],
      propertyOrdering: ["summary", "confidence", "recommended_lineup", "alternatives", "caveats"]
    }
  end

  defp lineup_slot_schema do
    %{
      type: "OBJECT",
      properties: %{
        player_id: %{type: "STRING"},
        player_name: %{type: "STRING"},
        position: %{type: "STRING", enum: @positions},
        position_label: %{type: "STRING"},
        champions: %{type: "ARRAY", items: %{type: "STRING"}},
        reason: %{type: "STRING"},
        evidence: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: ["player_id", "player_name", "position", "position_label", "champions", "reason"],
      propertyOrdering: [
        "player_id",
        "player_name",
        "position",
        "position_label",
        "champions",
        "reason",
        "evidence"
      ]
    }
  end

  defp normalize_response(response, context) do
    selected_players = Map.new(context.selected_players, &{&1.id, &1.name})

    %{
      "summary" => Map.get(response, "summary", ""),
      "confidence" => Map.get(response, "confidence", "low"),
      "recommended_lineup" =>
        response
        |> Map.get("recommended_lineup", [])
        |> Enum.map(&normalize_slot(&1, selected_players)),
      "alternatives" =>
        response
        |> Map.get("alternatives", [])
        |> Enum.map(&normalize_alternative(&1, selected_players)),
      "caveats" => Map.get(response, "caveats", [])
    }
  end

  defp normalize_alternative(alternative, selected_players) do
    %{
      "name" => Map.get(alternative, "name", "Alternative"),
      "notes" => Map.get(alternative, "notes", ""),
      "lineup" =>
        alternative
        |> Map.get("lineup", [])
        |> Enum.map(&normalize_slot(&1, selected_players))
    }
  end

  defp normalize_slot(slot, selected_players) do
    player_id = Map.get(slot, "player_id", "")

    %{
      "player_id" => player_id,
      "player_name" => Map.get(selected_players, player_id, Map.get(slot, "player_name", "")),
      "position" => Map.get(slot, "position", ""),
      "position_label" =>
        Map.get(slot, "position_label", position_label(Map.get(slot, "position"))),
      "champions" => Map.get(slot, "champions", []),
      "reason" => Map.get(slot, "reason", ""),
      "evidence" => Enum.map(Map.get(slot, "evidence", []), &humanize_evidence/1)
    }
  end

  defp humanize_evidence(evidence) when is_binary(evidence) do
    evidence
    |> String.replace("recent_non_shared_positions.", "Recent ")
    |> String.replace("recent_non_shared_top_champions.", "Recent ")
    |> String.replace("shared_positions.", "Shared ")
    |> String.replace("shared_top_champions.", "Shared ")
    |> String.replace("overall_positions.", "Overall ")
    |> String.replace("overall_top_champions.", "Overall ")
    |> String.replace("_", " ")
    |> String.replace(~r/\bTOP\b/, "top")
    |> String.replace(~r/\bJUNGLE\b/, "jungle")
    |> String.replace(~r/\bMIDDLE\b/, "mid")
    |> String.replace(~r/\bBOTTOM\b/, "bot")
    |> String.replace(~r/\bUTILITY\b/, "support")
    |> capitalize_first()
  end

  defp humanize_evidence(evidence), do: evidence

  defp capitalize_first(""), do: ""

  defp capitalize_first(<<first::utf8, rest::binary>>) do
    String.upcase(<<first::utf8>>) <> rest
  end

  defp position_label("TOP"), do: "Top"
  defp position_label("JUNGLE"), do: "Jungle"
  defp position_label("MIDDLE"), do: "Mid"
  defp position_label("BOTTOM"), do: "Bot"
  defp position_label("UTILITY"), do: "Support"
  defp position_label(_), do: ""
end
