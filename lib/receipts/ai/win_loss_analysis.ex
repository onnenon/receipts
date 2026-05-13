defmodule Receipts.AI.WinLossAnalysis do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{Queries, Queue, WinLossAnalysisCache, WinLossPromptLabRun}

  @cache_ttl_seconds 86_400
  @default_temperature 0.2
  @default_system_instruction """
  You are analyzing recent League of Legends games for a private friend group.
  Use only the supplied JSON. Write a retrospective about what past shared games
  prove: what went well, what went poorly, and which concrete games or stat lines
  support those claims. Improvement advice is secondary and should stay brief.
  Do not over-index on generic League advice. Prefer specific claims supported by
  shared games first, then recent individual form when it helps explain the pattern.
  Include kudos and fun-but-fair blame only when the stat lines support it.
  Be explicit about small samples and team context. Do not invent player history.
  All players in this friend group are men; use he/him/his pronouns for every player.
  Write blunt but fair user-facing prose. Never include raw JSON path names, snake_case keys,
  or dotted references in the response.
  """
  @default_prompt_template """
  Generate a game analysis for this selected group.

  Return JSON matching the schema. Use player_id values exactly as provided.
  Analyze the games as a retrospective, not primarily as coaching. Start with a
  one-sentence verdict, then explain what went well and what went poorly. Every
  major claim should include a receipt: a specific game, champion, stat line, or
  repeated stat pattern from the supplied context. Keep run-it-back advice short.
  """
  @context_block_definitions [
    %{
      "key" => "shared_group_stats",
      "label" => "Shared group stats",
      "description" => "Adds total shared game count and aggregate group win/loss record.",
      "schema" =>
        "shared_games: {count, group: {games, wins, losses, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score}}"
    },
    %{
      "key" => "shared_recent_games",
      "label" => "Recent shared games",
      "description" =>
        "Adds recent game-by-game breakdown for matches the whole group played together.",
      "schema" =>
        "shared_games.recent: [{match_id, played_at, group_win?, duration_seconds, participants: [{player_name, champion, position, win, kills, deaths, assists, cs, damage_dealt, vision_score}]}]"
    },
    %{
      "key" => "player_accounts",
      "label" => "Player accounts",
      "description" => "Adds each player's Riot account handles and regions.",
      "schema" => "accounts: [{game_name, tag_line, region}]"
    },
    %{
      "key" => "player_shared_summary",
      "label" => "Player shared summary",
      "description" => "Adds each player's aggregate stats across all shared games.",
      "schema" =>
        "shared_summary: {games, wins, losses, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score}"
    },
    %{
      "key" => "player_shared_loss_summary",
      "label" => "Player shared loss summary",
      "description" =>
        "Adds each player's stats from shared games the group lost — useful for diagnosing loss patterns.",
      "schema" =>
        "shared_loss_summary: {games, wins, losses, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score}"
    },
    %{
      "key" => "player_shared_positions",
      "label" => "Player shared positions",
      "description" => "Adds each player's role breakdown from shared games.",
      "schema" =>
        "shared_positions: [{position, games, wins, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs}]"
    },
    %{
      "key" => "player_recent_individual_summary",
      "label" => "Player recent individual summary",
      "description" => "Adds each player's recent aggregate stats outside the shared game set.",
      "schema" =>
        "recent_individual_summary: {games, wins, losses, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score}"
    },
    %{
      "key" => "player_recent_individual_positions",
      "label" => "Player recent individual positions",
      "description" => "Adds each player's recent role breakdown from individual games.",
      "schema" =>
        "recent_individual_positions: [{position, games, wins, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs}]"
    },
    %{
      "key" => "player_recent_shared_games",
      "label" => "Player recent shared games",
      "description" => "Adds each player's per-game stats from recent shared matches.",
      "schema" =>
        "recent_shared_games: [{champion, position, win, kills, deaths, assists, cs, damage_dealt, vision_score, game_datetime}]"
    },
    %{
      "key" => "player_recent_individual_games",
      "label" => "Player recent individual games",
      "description" =>
        "Adds each player's recent individual game results for current-form context.",
      "schema" =>
        "recent_individual_games: [{champion, position, win, kills, deaths, assists, cs, damage_dealt, vision_score, game_datetime}]"
    },
    %{
      "key" => "interpretation_notes",
      "label" => "Interpretation notes",
      "description" =>
        "Adds guardrails explaining shared-game context, individual form, and small sample handling.",
      "schema" => "note: string"
    }
  ]

  def analyze(player_ids, opts \\ []) do
    with {:ok, context} <- Queries.win_loss_analysis_context_for_players(player_ids, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  def prompt_lab_defaults(player_ids, opts \\ []) do
    with {:ok, _context} <- Queries.win_loss_analysis_context_for_players(player_ids, opts) do
      {:ok,
       %{
         system_instruction: default_system_instruction(),
         prompt_template: default_prompt_template(),
         context_config_json: encode_context_config(default_context_config(opts)),
         context_blocks: default_context_block_keys(),
         temperature: @default_temperature
       }}
    end
  end

  def trial_prompt(player_ids, opts, attrs) do
    system_instruction = Map.get(attrs, "system_instruction", default_system_instruction())
    prompt_template = Map.get(attrs, "prompt_template", default_prompt_template())
    temperature = parse_temperature(Map.get(attrs, "temperature", @default_temperature))
    context_config = context_config_from_attrs(opts, attrs)

    with {:ok, raw_context} <- Queries.win_loss_analysis_context_for_players(player_ids, opts),
         context = apply_context_config(raw_context, context_config),
         context_json = encode_context(context),
         {:ok, response} <-
           ai_client().generate_structured(
             render_prompt_template(prompt_template, context_json),
             response_schema(),
             ai_opts(system_instruction: system_instruction, temperature: temperature)
           ),
         analysis = normalize_response(response, raw_context),
         {:ok, record} <-
           store_prompt_lab_run(player_ids, opts, %{
             system_instruction: system_instruction,
             prompt_template: prompt_template,
             context: context,
             context_config: context_config,
             temperature: temperature,
             analysis: analysis
           }) do
      {:ok, prompt_lab_result(record)}
    end
  end

  def rate_run(run_id, rating) when rating in 1..5 do
    with {:ok, record} <- Ash.get(WinLossPromptLabRun, run_id),
         {:ok, _} <-
           record
           |> Ash.Changeset.for_update(:update_quality, %{quality_rating: rating})
           |> Ash.update() do
      :ok
    end
  end

  def prompt_lab_history(player_ids, opts \\ []) do
    player_ids
    |> cache_key(opts)
    |> prompt_lab_history_records()
    |> Enum.map(&prompt_lab_result/1)
  end

  def default_system_instruction, do: @default_system_instruction

  def default_prompt_template, do: @default_prompt_template

  def context_block_definitions, do: @context_block_definitions

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

  defp store_prompt_lab_run(player_ids, opts, attrs) do
    WinLossPromptLabRun
    |> Ash.Changeset.for_create(:create, %{
      group_key: cache_key(player_ids, opts),
      player_ids: normalize_player_ids(player_ids),
      filters: cache_filters(opts),
      system_instruction: attrs.system_instruction,
      prompt_template: attrs.prompt_template,
      context: attrs.context,
      context_config: attrs.context_config,
      temperature: attrs.temperature,
      analysis: attrs.analysis,
      generated_at: DateTime.utc_now()
    })
    |> Ash.create()
  end

  defp prompt_lab_history_records(group_key) do
    WinLossPromptLabRun
    |> Ash.Query.filter(group_key == ^group_key)
    |> Ash.Query.sort(generated_at: :desc)
    |> Ash.Query.limit(10)
    |> Ash.read!()
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

  defp prompt_lab_result(record) do
    %{
      id: record.id,
      analysis: clean_analysis(record.analysis),
      generated_at: record.generated_at,
      system_instruction: record.system_instruction,
      prompt_template: record.prompt_template,
      context: record.context,
      context_config: record.context_config,
      temperature: record.temperature,
      quality_rating: record.quality_rating
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

  defp ai_opts(overrides \\ []) do
    [
      system_instruction:
        Keyword.get(overrides, :system_instruction, default_system_instruction()),
      temperature: Keyword.get(overrides, :temperature, @default_temperature),
      connect_timeout: 10_000,
      receive_timeout: 90_000
    ]
  end

  defp prompt(context) do
    render_prompt_template(default_prompt_template(), Jason.encode!(context))
  end

  defp response_schema do
    %{
      type: "OBJECT",
      properties: %{
        summary: %{type: "STRING"},
        confidence: %{type: "STRING", enum: ["low", "medium", "high"]},
        went_well: %{type: "ARRAY", items: insight_schema()},
        went_poorly: %{type: "ARRAY", items: insight_schema()},
        receipts: %{type: "ARRAY", items: receipt_schema()},
        player_readouts: %{type: "ARRAY", items: player_readout_schema()},
        run_it_back: %{type: "ARRAY", items: %{type: "STRING"}},
        caveats: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: [
        "summary",
        "confidence",
        "went_well",
        "went_poorly",
        "receipts",
        "player_readouts",
        "run_it_back",
        "caveats"
      ],
      propertyOrdering: [
        "summary",
        "confidence",
        "went_well",
        "went_poorly",
        "receipts",
        "player_readouts",
        "run_it_back",
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
        evidence_strength: %{type: "STRING", enum: ["low", "medium", "high"]}
      },
      required: ["title", "details", "evidence", "evidence_strength"],
      propertyOrdering: ["title", "details", "evidence", "evidence_strength"]
    }
  end

  defp receipt_schema do
    %{
      type: "OBJECT",
      properties: %{
        label: %{type: "STRING"},
        player_name: %{type: "STRING"},
        champion: %{type: "STRING"},
        statline: %{type: "STRING"},
        result: %{type: "STRING"},
        takeaway: %{type: "STRING"}
      },
      required: ["label", "player_name", "champion", "statline", "result", "takeaway"],
      propertyOrdering: ["label", "player_name", "champion", "statline", "result", "takeaway"]
    }
  end

  defp player_readout_schema do
    %{
      type: "OBJECT",
      properties: %{
        player_id: %{type: "STRING"},
        player_name: %{type: "STRING"},
        good: %{type: "STRING"},
        bad: %{type: "STRING"},
        receipt: %{type: "STRING"},
        trend: %{type: "STRING", enum: ["carrying", "stable", "struggling", "volatile"]},
        evidence: %{type: "ARRAY", items: %{type: "STRING"}}
      },
      required: ["player_id", "player_name", "good", "bad", "receipt", "trend", "evidence"],
      propertyOrdering: [
        "player_id",
        "player_name",
        "good",
        "bad",
        "receipt",
        "trend",
        "evidence"
      ]
    }
  end

  defp normalize_response(response, context) do
    selected_players = Map.new(context.selected_players, &{&1.id, &1.name})

    %{
      "summary" => clean_prose(Map.get(response, "summary", "")),
      "confidence" => Map.get(response, "confidence", "low"),
      "went_well" => Enum.map(Map.get(response, "went_well", []), &clean_insight/1),
      "went_poorly" => Enum.map(Map.get(response, "went_poorly", []), &clean_insight/1),
      "receipts" => Enum.map(Map.get(response, "receipts", []), &clean_receipt/1),
      "player_readouts" =>
        response
        |> Map.get("player_readouts", [])
        |> Enum.map(&clean_player_readout(&1, selected_players)),
      "run_it_back" => Enum.map(Map.get(response, "run_it_back", []), &clean_prose/1),
      "caveats" => Enum.map(Map.get(response, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_analysis(analysis) when is_map(analysis) do
    %{
      "summary" => clean_prose(Map.get(analysis, "summary", "")),
      "confidence" => Map.get(analysis, "confidence", "low"),
      "went_well" =>
        analysis
        |> Map.get("went_well", Map.get(analysis, "carry_highlights", []))
        |> Enum.map(&clean_insight/1),
      "went_poorly" =>
        analysis
        |> Map.get("went_poorly", Map.get(analysis, "loss_causes", []))
        |> Enum.map(&clean_insight/1),
      "receipts" =>
        analysis
        |> Map.get("receipts", [])
        |> Enum.map(&clean_receipt/1),
      "player_readouts" =>
        analysis
        |> Map.get("player_readouts", [])
        |> Enum.map(&clean_player_readout(&1, %{})),
      "run_it_back" =>
        analysis
        |> Map.get("run_it_back", Map.get(analysis, "recommendations", []))
        |> Enum.map(&clean_prose/1),
      "caveats" => Enum.map(Map.get(analysis, "caveats", []), &clean_prose/1)
    }
  end

  defp clean_analysis(_analysis) do
    %{
      "summary" => "",
      "confidence" => "low",
      "went_well" => [],
      "went_poorly" => [],
      "receipts" => [],
      "player_readouts" => [],
      "run_it_back" => [],
      "caveats" => []
    }
  end

  defp clean_player_readout(readout, selected_players) when is_map(readout) do
    player_id = Map.get(readout, "player_id", "")

    %{
      "player_id" => player_id,
      "player_name" => Map.get(selected_players, player_id, Map.get(readout, "player_name", "")),
      "good" => clean_prose(Map.get(readout, "good", "")),
      "bad" => clean_prose(Map.get(readout, "bad", "")),
      "receipt" => clean_prose(Map.get(readout, "receipt", "")),
      "verdict" => clean_prose(Map.get(readout, "verdict", "")),
      "trend" => Map.get(readout, "trend", "stable"),
      "evidence" => Enum.map(Map.get(readout, "evidence", []), &clean_prose/1)
    }
  end

  defp clean_player_readout(_readout, _selected_players) do
    %{
      "player_id" => "",
      "player_name" => "",
      "good" => "",
      "bad" => "",
      "receipt" => "",
      "verdict" => "",
      "trend" => "stable",
      "evidence" => []
    }
  end

  defp clean_insight(insight) when is_map(insight) do
    evidence_strength =
      Map.get(
        insight,
        "evidence_strength",
        Map.get(insight, "impact", Map.get(insight, "severity", "medium"))
      )

    %{
      "title" => clean_prose(Map.get(insight, "title", "")),
      "details" => clean_prose(Map.get(insight, "details", "")),
      "evidence" => Enum.map(Map.get(insight, "evidence", []), &clean_prose/1),
      "evidence_strength" => evidence_strength
    }
  end

  defp clean_insight(_insight) do
    %{"title" => "", "details" => "", "evidence" => [], "evidence_strength" => "medium"}
  end

  defp clean_receipt(receipt) when is_map(receipt) do
    %{
      "label" => clean_prose(Map.get(receipt, "label", "")),
      "player_name" => clean_prose(Map.get(receipt, "player_name", "")),
      "champion" => clean_prose(Map.get(receipt, "champion", "")),
      "statline" => clean_prose(Map.get(receipt, "statline", "")),
      "result" => clean_prose(Map.get(receipt, "result", "")),
      "takeaway" => clean_prose(Map.get(receipt, "takeaway", ""))
    }
  end

  defp clean_receipt(_receipt) do
    %{
      "label" => "",
      "player_name" => "",
      "champion" => "",
      "statline" => "",
      "result" => "",
      "takeaway" => ""
    }
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

  defp encode_context(context), do: Jason.encode!(context, pretty: true)

  defp encode_context_config(context_config), do: Jason.encode!(context_config, pretty: true)

  defp context_config_from_attrs(opts, attrs) do
    cond do
      Map.has_key?(attrs, "context_blocks") ->
        selected_context_config(opts, Map.get(attrs, "context_blocks", []))

      true ->
        case Jason.decode(Map.get(attrs, "context_config_json", "")) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _ -> default_context_config(opts)
        end
    end
  end

  defp selected_context_config(opts, selected_keys) do
    selected_keys =
      selected_keys
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    %{
      "version" => 1,
      "mode" => "selected_win_loss_analysis_context",
      "filters" => cache_filters(opts),
      "blocks" =>
        Enum.map(@context_block_definitions, fn block ->
          %{
            "key" => block["key"],
            "enabled" => MapSet.member?(selected_keys, block["key"]),
            "params" => %{}
          }
        end)
    }
  end

  defp default_context_config(opts) do
    %{
      "version" => 1,
      "mode" => "default_win_loss_analysis_context",
      "filters" => cache_filters(opts),
      "blocks" =>
        Enum.map(@context_block_definitions, fn block ->
          %{"key" => block["key"], "enabled" => true, "params" => %{}}
        end)
    }
  end

  defp default_context_block_keys do
    Enum.map(@context_block_definitions, & &1["key"])
  end

  defp apply_context_config(context, context_config) do
    enabled = enabled_context_blocks(context_config)

    base = %{
      filters: context.filters,
      selected_players: context.selected_players
    }

    base
    |> maybe_put_shared_games(context.shared_games, enabled)
    |> maybe_put_context(:notes, context.notes, enabled, "interpretation_notes")
    |> Map.put(:players, Enum.map(context.players, &filter_player_context(&1, enabled)))
  end

  defp maybe_put_shared_games(ctx, shared_games, enabled) do
    include_stats? = MapSet.member?(enabled, "shared_group_stats")
    include_recent? = MapSet.member?(enabled, "shared_recent_games")

    cond do
      include_stats? and include_recent? ->
        Map.put(ctx, :shared_games, shared_games)

      include_stats? ->
        Map.put(ctx, :shared_games, Map.drop(shared_games, [:recent]))

      include_recent? ->
        Map.put(ctx, :shared_games, %{
          count: shared_games.count,
          recent: shared_games.recent
        })

      true ->
        ctx
    end
  end

  defp filter_player_context(player, enabled) do
    %{id: player.id, name: player.name}
    |> maybe_put_context(:accounts, player.accounts, enabled, "player_accounts")
    |> maybe_put_context(:shared_summary, player.shared_summary, enabled, "player_shared_summary")
    |> maybe_put_context(
      :shared_loss_summary,
      player.shared_loss_summary,
      enabled,
      "player_shared_loss_summary"
    )
    |> maybe_put_context(
      :shared_positions,
      player.shared_positions,
      enabled,
      "player_shared_positions"
    )
    |> maybe_put_context(
      :recent_individual_summary,
      player.recent_individual_summary,
      enabled,
      "player_recent_individual_summary"
    )
    |> maybe_put_context(
      :recent_individual_positions,
      player.recent_individual_positions,
      enabled,
      "player_recent_individual_positions"
    )
    |> maybe_put_context(
      :recent_shared_games,
      player.recent_shared_games,
      enabled,
      "player_recent_shared_games"
    )
    |> maybe_put_context(
      :recent_individual_games,
      player.recent_individual_games,
      enabled,
      "player_recent_individual_games"
    )
  end

  defp maybe_put_context(ctx, key, value, enabled, block_key) do
    if MapSet.member?(enabled, block_key), do: Map.put(ctx, key, value), else: ctx
  end

  defp enabled_context_blocks(%{"blocks" => blocks}) do
    blocks
    |> Enum.filter(&Map.get(&1, "enabled", false))
    |> Enum.map(&Map.get(&1, "key"))
    |> MapSet.new()
  end

  defp enabled_context_blocks(_context_config), do: MapSet.new(default_context_block_keys())

  defp render_prompt_template(template, context_json) do
    template
    |> strip_legacy_context_placeholder()
    |> then(&(&1 <> "\n\nContext:\n" <> context_json))
  end

  defp strip_legacy_context_placeholder(template) do
    template
    |> String.replace(~r/\n*Context:\s*\{\{context_json\}\}\s*/i, "")
    |> String.replace("{{context_json}}", "")
    |> String.trim()
  end

  defp parse_temperature(value) when is_float(value), do: clamp_temperature(value)
  defp parse_temperature(value) when is_integer(value), do: clamp_temperature(value / 1)

  defp parse_temperature(value) when is_binary(value) do
    case Float.parse(value) do
      {temperature, ""} -> clamp_temperature(temperature)
      _ -> @default_temperature
    end
  end

  defp parse_temperature(_value), do: @default_temperature

  defp clamp_temperature(value) when value < 0.0, do: 0.0
  defp clamp_temperature(value) when value > 2.0, do: 2.0
  defp clamp_temperature(value), do: value
end
