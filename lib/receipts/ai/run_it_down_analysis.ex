defmodule Receipts.AI.RunItDownAnalysis do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{Queries, Queue, RunItDownAnalysisCache}

  @cache_ttl_seconds 86_400
  @default_temperature 0.35
  @default_system_instruction """
  You are answering a private League of Legends friend group's important pre-game question:
  "Will they run it down?"
  Use only the supplied JSON. Be honest, specific, and slightly funny, but do not roast beyond
  what the data supports. The meter is 0 = Feed and 100 = Carry. Weigh exact champion/position
  games first, then exact champion across other positions, then same-position similar champion
  history, then recent overall form. If the exact champion sample is zero games, still give a
  useful read from the weaker evidence and clearly say the sample is unproven.
  All players in this friend group are men; use he/him/his pronouns.
  Write user-facing prose. Never include raw JSON path names, snake_case keys, or dotted references.
  """
  @default_prompt_template """
  Generate a "Will they run it down?" analysis for this player, champion, and selected position set.

  Return JSON matching the schema. Use a carry_score from 0 to 100 where 0 is Feed,
  50 is coin flip, and 100 is Carry. Every major claim should include a receipt:
  exact champion stats, same-position patterns, similar champion performance, or recent games.
  If there are no exact games on the selected champion, do not refuse; grade the risk from
  same-position and recent overall history.

  Context JSON:
  {{context_json}}
  """

  def analyze(player_id, champion_key, positions, opts \\ []) do
    with {:ok, context} <-
           Queries.run_it_down_analysis_context(player_id, champion_key, positions, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  def fetch_or_generate(player_id, champion_key, positions, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    case {force?, cached_record(player_id, champion_key, positions, opts)} do
      {false, %RunItDownAnalysisCache{} = record} ->
        {:ok, analysis_result(record, cached?: true)}

      _ ->
        generate_and_store(player_id, champion_key, positions, opts)
    end
  end

  def history(player_id, champion_key, positions, opts \\ []) do
    player_id
    |> cache_key(champion_key, positions, opts)
    |> history_records()
    |> Enum.map(&analysis_result(&1, cached?: fresh?(&1)))
  end

  def cache_key(player_id, champion_key, positions, opts \\ []) do
    %{
      "player_id" => to_string(player_id),
      "champion_key" => normalize_champion_key(champion_key),
      "positions" => normalize_positions(positions),
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

  def fresh?(%RunItDownAnalysisCache{generated_at: %DateTime{} = generated_at}) do
    DateTime.diff(DateTime.utc_now(), generated_at, :second) < @cache_ttl_seconds
  end

  def fresh?(_record), do: false

  defp generate_and_store(player_id, champion_key, positions, opts) do
    opts = Keyword.delete(opts, :force)

    with {:ok, context} <-
           Queries.run_it_down_analysis_context(player_id, champion_key, positions, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()),
         analysis = normalize_response(response, context),
         {:ok, record} <- store_analysis(player_id, context, opts, analysis) do
      {:ok, analysis_result(record, cached?: false)}
    end
  end

  defp cached_record(player_id, champion_key, positions, opts) do
    player_id
    |> cache_key(champion_key, positions, opts)
    |> history_records(1)
    |> Enum.find(&fresh?/1)
  end

  defp history_records(cache_key, limit \\ nil) do
    RunItDownAnalysisCache
    |> Ash.Query.filter(cache_key == ^cache_key)
    |> Ash.Query.sort(generated_at: :desc)
    |> maybe_limit(limit)
    |> Ash.read!()
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  defp store_analysis(player_id, context, opts, analysis) do
    RunItDownAnalysisCache
    |> Ash.Changeset.for_create(:create, %{
      cache_key:
        cache_key(
          player_id,
          context.selected_champion.key,
          Enum.map(context.selected_positions, & &1.key),
          opts
        ),
      player_id: to_string(player_id),
      champion_id: context.selected_champion.id,
      position: context.selected_positions |> Enum.map(& &1.key) |> Enum.join(","),
      positions: Enum.map(context.selected_positions, & &1.key),
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

  defp ai_client do
    Application.get_env(:receipts, :ai_client, Receipts.AI.Gemini)
  end

  defp ai_opts do
    [
      system_instruction: @default_system_instruction,
      temperature: @default_temperature,
      connect_timeout: 10_000,
      receive_timeout: 90_000
    ]
  end

  defp prompt(context) do
    @default_prompt_template
    |> String.replace("{{context_json}}", Jason.encode!(context))
  end

  defp response_schema do
    %{
      type: "OBJECT",
      properties: %{
        verdict: %{type: "STRING"},
        summary: %{type: "STRING"},
        carry_score: %{type: "INTEGER"},
        confidence: %{type: "STRING", enum: ["low", "medium", "high"]},
        risk_label: %{type: "STRING"},
        evidence: %{type: "ARRAY", items: %{type: "STRING"}},
        similar_champ_notes: %{type: "ARRAY", items: %{type: "STRING"}},
        advice: %{type: "ARRAY", items: %{type: "STRING"}},
        caveats: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: [
        "verdict",
        "summary",
        "carry_score",
        "confidence",
        "risk_label",
        "evidence",
        "similar_champ_notes",
        "advice",
        "caveats"
      ],
      propertyOrdering: [
        "verdict",
        "summary",
        "carry_score",
        "confidence",
        "risk_label",
        "evidence",
        "similar_champ_notes",
        "advice",
        "caveats"
      ]
    }
  end

  defp normalize_response(response, _context) do
    %{
      "verdict" => clean_prose(Map.get(response, "verdict", "")),
      "summary" => clean_prose(Map.get(response, "summary", "")),
      "carry_score" => clamp_score(Map.get(response, "carry_score", 50)),
      "confidence" => Map.get(response, "confidence", "low"),
      "risk_label" => clean_prose(Map.get(response, "risk_label", "Coin flip")),
      "evidence" => Enum.map(Map.get(response, "evidence", []), &clean_prose/1),
      "similar_champ_notes" =>
        Enum.map(Map.get(response, "similar_champ_notes", []), &clean_prose/1),
      "advice" => Enum.map(Map.get(response, "advice", []), &clean_prose/1),
      "caveats" => Enum.map(Map.get(response, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_analysis(analysis) when is_map(analysis), do: normalize_response(analysis, %{})

  defp clean_analysis(_analysis) do
    %{
      "verdict" => "",
      "summary" => "",
      "carry_score" => 50,
      "confidence" => "low",
      "risk_label" => "Coin flip",
      "evidence" => [],
      "similar_champ_notes" => [],
      "advice" => [],
      "caveats" => []
    }
  end

  defp clamp_score(score) when is_integer(score), do: score |> max(0) |> min(100)

  defp clamp_score(score) when is_float(score) do
    score |> round() |> clamp_score()
  end

  defp clamp_score(score) when is_binary(score) do
    case Integer.parse(score) do
      {parsed, _rest} -> clamp_score(parsed)
      :error -> 50
    end
  end

  defp clamp_score(_score), do: 50

  defp clean_prose(value) when is_binary(value) do
    value
    |> String.replace(~r/\bUTILITY\b/, "Support")
    |> String.replace(~r/\bMIDDLE\b/, "Mid")
    |> String.replace(~r/\bBOTTOM\b/, "Bot")
    |> String.replace(~r/\bJUNGLE\b/, "Jungle")
    |> String.replace(~r/\bTOP\b/, "Top")
    |> String.replace(~r/\bshe\b/i, "he")
    |> String.replace(~r/\bher\b/i, "his")
    |> String.replace("_", " ")
  end

  defp clean_prose(value), do: to_string(value || "")

  defp normalize_champion_key(value) do
    value |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
  end

  defp normalize_positions(positions) when is_list(positions) do
    positions
    |> Enum.map(&normalize_position/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_positions(position), do: normalize_positions([position])

  defp normalize_position(position) when is_binary(position) do
    position |> String.trim() |> String.upcase()
  end

  defp normalize_position(_position), do: ""
end
