defmodule Receipts.AI.CompSuggestion do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{CompSuggestionCache, Queries, Queue}

  @positions ~w(TOP JUNGLE MIDDLE BOTTOM UTILITY)
  @cache_ttl_seconds 86_400

  def suggest(player_ids, opts \\ []) do
    with {:ok, context} <- Queries.comp_suggestion_context_for_players(player_ids, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  def fetch_or_generate(player_ids, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    case {force?, cached_record(player_ids, opts)} do
      {false, %CompSuggestionCache{} = record} ->
        {:ok, suggestion_result(record, cached?: true)}

      _ ->
        generate_and_store(player_ids, opts)
    end
  end

  def history(player_ids, opts \\ []) do
    player_ids
    |> cache_key(opts)
    |> history_records()
    |> Enum.map(&suggestion_result(&1, cached?: fresh?(&1)))
  end

  def cache_key(player_ids, opts \\ []) do
    %{
      "player_ids" => player_ids |> normalize_player_ids() |> Enum.sort(),
      "filters" => cache_filters(opts)
    }
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def cache_filters(opts \\ []) do
    queue_types =
      opts
      |> Keyword.get(:queue_types, Queue.default_queues())
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    %{
      "queue_types" => queue_types,
      "from_year" => Keyword.get(opts, :from_year),
      "to_year" => Keyword.get(opts, :to_year)
    }
  end

  def fresh?(%CompSuggestionCache{generated_at: %DateTime{} = generated_at}) do
    DateTime.diff(DateTime.utc_now(), generated_at, :second) < @cache_ttl_seconds
  end

  def fresh?(_record), do: false

  defp generate_and_store(player_ids, opts) do
    opts = Keyword.delete(opts, :force)

    with {:ok, suggestion} <- suggest(player_ids, opts),
         {:ok, record} <- store_suggestion(player_ids, opts, suggestion) do
      {:ok, suggestion_result(record, cached?: false)}
    end
  end

  defp cached_record(player_ids, opts) do
    player_ids
    |> cache_key(opts)
    |> history_records(1)
    |> Enum.find(&fresh?/1)
  end

  defp history_records(cache_key, limit \\ nil) do
    CompSuggestionCache
    |> Ash.Query.filter(cache_key == ^cache_key)
    |> Ash.Query.sort(generated_at: :desc)
    |> maybe_limit(limit)
    |> Ash.read!()
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  defp store_suggestion(player_ids, opts, suggestion) do
    CompSuggestionCache
    |> Ash.Changeset.for_create(:create, %{
      cache_key: cache_key(player_ids, opts),
      player_ids: normalize_player_ids(player_ids),
      filters: cache_filters(opts),
      suggestion: suggestion,
      generated_at: DateTime.utc_now()
    })
    |> Ash.create()
  end

  defp suggestion_result(record, opts) do
    cached? = Keyword.fetch!(opts, :cached?)

    %{
      id: record.id,
      suggestion: clean_suggestion(record.suggestion),
      generated_at: record.generated_at,
      cached?: cached?,
      fresh?: fresh?(record)
    }
  end

  defp normalize_player_ids(player_ids) do
    player_ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
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
      All players in this friend group are men; use he/him/his pronouns for every player.
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
      "summary" => clean_prose(Map.get(response, "summary", "")),
      "confidence" => Map.get(response, "confidence", "low"),
      "recommended_lineup" =>
        response
        |> Map.get("recommended_lineup", [])
        |> Enum.map(&normalize_slot(&1, selected_players)),
      "alternatives" =>
        response
        |> Map.get("alternatives", [])
        |> Enum.map(&normalize_alternative(&1, selected_players)),
      "caveats" => Enum.map(Map.get(response, "caveats", []), &clean_prose/1)
    }
  end

  defp normalize_alternative(alternative, selected_players) do
    %{
      "name" => Map.get(alternative, "name", "Alternative"),
      "notes" => clean_prose(Map.get(alternative, "notes", "")),
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
      "position_label" => position_label(Map.get(slot, "position")),
      "champions" => Map.get(slot, "champions", []),
      "reason" => clean_prose(Map.get(slot, "reason", "")),
      "evidence" => Enum.map(Map.get(slot, "evidence", []), &humanize_evidence/1)
    }
  end

  defp clean_suggestion(suggestion) when is_map(suggestion) do
    %{
      "summary" => clean_prose(Map.get(suggestion, "summary", "")),
      "confidence" => Map.get(suggestion, "confidence", "low"),
      "recommended_lineup" =>
        suggestion
        |> Map.get("recommended_lineup", [])
        |> Enum.map(&clean_slot/1),
      "alternatives" =>
        suggestion
        |> Map.get("alternatives", [])
        |> Enum.map(&clean_alternative/1),
      "caveats" => Enum.map(Map.get(suggestion, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_suggestion(_suggestion) do
    %{
      "summary" => "",
      "confidence" => "low",
      "recommended_lineup" => [],
      "alternatives" => [],
      "caveats" => []
    }
  end

  defp clean_alternative(alternative) when is_map(alternative) do
    %{
      "name" => Map.get(alternative, "name", "Alternative"),
      "notes" => clean_prose(Map.get(alternative, "notes", "")),
      "lineup" =>
        alternative
        |> Map.get("lineup", [])
        |> Enum.map(&clean_slot/1)
    }
  end

  defp clean_alternative(_alternative),
    do: %{"name" => "Alternative", "notes" => "", "lineup" => []}

  defp clean_slot(slot) when is_map(slot) do
    position = Map.get(slot, "position", "")

    %{
      "player_id" => Map.get(slot, "player_id", ""),
      "player_name" => Map.get(slot, "player_name", ""),
      "position" => position,
      "position_label" => position_label(position),
      "champions" => Map.get(slot, "champions", []),
      "reason" => clean_prose(Map.get(slot, "reason", "")),
      "evidence" => Enum.map(Map.get(slot, "evidence", []), &humanize_evidence/1)
    }
  end

  defp clean_slot(_slot) do
    %{
      "player_id" => "",
      "player_name" => "",
      "position" => "",
      "position_label" => "",
      "champions" => [],
      "reason" => "",
      "evidence" => []
    }
  end

  defp humanize_evidence(evidence) when is_binary(evidence) do
    evidence
    |> String.replace(~r/^Recent non-shared games:\s*/i, "Recent ")
    |> String.replace(~r/^Shared games:\s*/i, "Shared ")
    |> String.replace(~r/^Overall games:\s*/i, "Overall ")
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
    |> normalize_evidence_parenthetical()
    |> clean_prose()
    |> capitalize_first()
  end

  defp humanize_evidence(evidence), do: evidence

  defp normalize_evidence_parenthetical(evidence) do
    case Regex.run(~r/^(Recent|Shared|Overall)\s+([^:()]+)\s+\((.+)\)$/i, evidence) do
      [_, scope, subject, details] ->
        "#{capitalize_first(String.downcase(scope))} #{evidence_subject(subject)}: #{details}"

      _ ->
        evidence
    end
  end

  defp evidence_subject(subject) do
    case subject |> String.trim() |> String.downcase() do
      "top" -> "top"
      "jungle" -> "jungle"
      "middle" -> "mid"
      "mid" -> "mid"
      "bottom" -> "bot"
      "bot" -> "bot"
      "utility" -> "support"
      "support" -> "support"
      _ -> String.trim(subject)
    end
  end

  defp clean_prose(text) when is_binary(text) do
    text
    |> String.replace(~r/\b[Ss]he\b/, "he")
    |> String.replace(~r/\b[Hh]ers\b/, "his")
    |> String.replace(~r/\b[Hh]er\b/, "his")
    |> String.replace(~r/\butility\b/i, "support")
  end

  defp clean_prose(text), do: text

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
