defmodule Receipts.AI.WinLossAnalysis do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{Queries, Queue, WinLossAnalysisCache}

  @cache_ttl_seconds 86_400

  def analyze(player_ids, opts \\ []) do
    with {:ok, context} <- Queries.win_loss_analysis_context_for_players(player_ids, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  def fetch_or_generate(player_ids, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    case {force?, cached_record(player_ids, opts)} do
      {false, %WinLossAnalysisCache{} = record} ->
        {:ok, analysis_result(record, cached?: true)}

      _ ->
        generate_and_store(player_ids, opts)
    end
  end

  def history(player_ids, opts \\ []) do
    player_ids
    |> cache_key(opts)
    |> history_records()
    |> Enum.map(&analysis_result(&1, cached?: fresh?(&1)))
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
      "to_year" => Keyword.get(opts, :to_year),
      "recent_match_limit" => Keyword.get(opts, :recent_match_limit, 20),
      "recent_player_game_limit" => Keyword.get(opts, :recent_player_game_limit, 20)
    }
  end

  def fresh?(%WinLossAnalysisCache{generated_at: %DateTime{} = generated_at}) do
    DateTime.diff(DateTime.utc_now(), generated_at, :second) < @cache_ttl_seconds
  end

  def fresh?(_record), do: false

  defp generate_and_store(player_ids, opts) do
    opts = Keyword.delete(opts, :force)

    with {:ok, analysis} <- analyze(player_ids, opts),
         {:ok, record} <- store_analysis(player_ids, opts, analysis) do
      {:ok, analysis_result(record, cached?: false)}
    end
  end

  defp cached_record(player_ids, opts) do
    player_ids
    |> cache_key(opts)
    |> history_records(1)
    |> Enum.find(&fresh?/1)
  end

  defp history_records(cache_key, limit \\ nil) do
    WinLossAnalysisCache
    |> Ash.Query.filter(cache_key == ^cache_key)
    |> Ash.Query.sort(generated_at: :desc)
    |> maybe_limit(limit)
    |> Ash.read!()
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  defp store_analysis(player_ids, opts, analysis) do
    WinLossAnalysisCache
    |> Ash.Changeset.for_create(:create, %{
      cache_key: cache_key(player_ids, opts),
      player_ids: normalize_player_ids(player_ids),
      filters: cache_filters(opts),
      analysis: analysis,
      generated_at: DateTime.utc_now()
    })
    |> Ash.create()
  end

  defp analysis_result(record, opts) do
    cached? = Keyword.fetch!(opts, :cached?)

    %{
      id: record.id,
      analysis: clean_analysis(record.analysis),
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
      You are analyzing recent League of Legends games for a private friend group.
      Use only the supplied JSON. Give balanced feedback: celebrate who is carrying
      or making games easier, call out who is underperforming, and point lighthearted
      blame where the stat lines support it. Do not favor wins or losses by default;
      explain what is working in wins, what is breaking in losses, and what concrete
      adjustments the group should try. Anchor claims in stat lines from recent shared
      games first, then recent individual form.
      Be explicit about small samples and team context. Do not invent player history.
      All players in this friend group are men; use he/him/his pronouns for every player.
      Write blunt but fair user-facing prose. Never include raw JSON path names, snake_case keys,
      or dotted references in the response.
      """,
      temperature: 0.2,
      connect_timeout: 10_000,
      receive_timeout: 90_000
    ]
  end

  defp prompt(context) do
    """
    Generate a game analysis for this selected group.

    Return JSON matching the schema. Use player_id values exactly as provided.
    Cover both wins and losses without treating either as more important by default.
    Include kudos, useful feedback, and fun-but-fair blame for who is carrying hard
    and who is not pulling weight.

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
        loss_causes: %{type: "ARRAY", items: insight_schema()},
        player_readouts: %{type: "ARRAY", items: player_readout_schema()},
        carry_highlights: %{type: "ARRAY", items: insight_schema()},
        recommendations: %{type: "ARRAY", items: %{type: "STRING"}},
        caveats: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: [
        "summary",
        "confidence",
        "loss_causes",
        "player_readouts",
        "carry_highlights",
        "recommendations",
        "caveats"
      ],
      propertyOrdering: [
        "summary",
        "confidence",
        "loss_causes",
        "player_readouts",
        "carry_highlights",
        "recommendations",
        "caveats"
      ]
    }
  end

  defp insight_schema do
    %{
      type: "OBJECT",
      properties: %{
        title: %{type: "STRING"},
        details: %{type: "STRING"},
        evidence: %{type: "ARRAY", items: %{type: "STRING"}},
        severity: %{type: "STRING", enum: ["low", "medium", "high"]}
      },
      required: ["title", "details", "evidence", "severity"],
      propertyOrdering: ["title", "details", "evidence", "severity"]
    }
  end

  defp player_readout_schema do
    %{
      type: "OBJECT",
      properties: %{
        player_id: %{type: "STRING"},
        player_name: %{type: "STRING"},
        verdict: %{type: "STRING"},
        trend: %{type: "STRING", enum: ["carrying", "stable", "struggling", "volatile"]},
        evidence: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: ["player_id", "player_name", "verdict", "trend", "evidence"],
      propertyOrdering: ["player_id", "player_name", "verdict", "trend", "evidence"]
    }
  end

  defp normalize_response(response, context) do
    selected_players = Map.new(context.selected_players, &{&1.id, &1.name})

    %{
      "summary" => clean_prose(Map.get(response, "summary", "")),
      "confidence" => Map.get(response, "confidence", "low"),
      "loss_causes" => Enum.map(Map.get(response, "loss_causes", []), &clean_insight/1),
      "player_readouts" =>
        response
        |> Map.get("player_readouts", [])
        |> Enum.map(&clean_player_readout(&1, selected_players)),
      "carry_highlights" => Enum.map(Map.get(response, "carry_highlights", []), &clean_insight/1),
      "recommendations" => Enum.map(Map.get(response, "recommendations", []), &clean_prose/1),
      "caveats" => Enum.map(Map.get(response, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_analysis(analysis) when is_map(analysis) do
    %{
      "summary" => clean_prose(Map.get(analysis, "summary", "")),
      "confidence" => Map.get(analysis, "confidence", "low"),
      "loss_causes" => Enum.map(Map.get(analysis, "loss_causes", []), &clean_insight/1),
      "player_readouts" =>
        analysis
        |> Map.get("player_readouts", [])
        |> Enum.map(&clean_player_readout(&1, %{})),
      "carry_highlights" => Enum.map(Map.get(analysis, "carry_highlights", []), &clean_insight/1),
      "recommendations" => Enum.map(Map.get(analysis, "recommendations", []), &clean_prose/1),
      "caveats" => Enum.map(Map.get(analysis, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_analysis(_analysis) do
    %{
      "summary" => "",
      "confidence" => "low",
      "loss_causes" => [],
      "player_readouts" => [],
      "carry_highlights" => [],
      "recommendations" => [],
      "caveats" => []
    }
  end

  defp clean_player_readout(readout, selected_players) when is_map(readout) do
    player_id = Map.get(readout, "player_id", "")

    %{
      "player_id" => player_id,
      "player_name" => Map.get(selected_players, player_id, Map.get(readout, "player_name", "")),
      "verdict" => clean_prose(Map.get(readout, "verdict", "")),
      "trend" => Map.get(readout, "trend", "stable"),
      "evidence" => Enum.map(Map.get(readout, "evidence", []), &clean_prose/1)
    }
  end

  defp clean_player_readout(_readout, _selected_players) do
    %{
      "player_id" => "",
      "player_name" => "",
      "verdict" => "",
      "trend" => "stable",
      "evidence" => []
    }
  end

  defp clean_insight(insight) when is_map(insight) do
    %{
      "title" => clean_prose(Map.get(insight, "title", "")),
      "details" => clean_prose(Map.get(insight, "details", "")),
      "evidence" => Enum.map(Map.get(insight, "evidence", []), &clean_prose/1),
      "severity" => Map.get(insight, "severity", "medium")
    }
  end

  defp clean_insight(_insight) do
    %{"title" => "", "details" => "", "evidence" => [], "severity" => "medium"}
  end

  defp clean_prose(value) when is_binary(value) do
    value
    |> String.replace(~r/\bUTILITY\b/, "Support")
    |> String.replace(~r/\bMIDDLE\b/, "Mid")
    |> String.replace(~r/\bBOTTOM\b/, "Bot")
    |> String.replace(~r/\bJUNGLE\b/, "Jungle")
    |> String.replace(~r/\bTOP\b/, "Top")
    |> String.replace(~r/\bshe\b/i, "he")
    |> String.replace(~r/\bher\b/i, "his")
  end

  defp clean_prose(value), do: to_string(value || "")
end
