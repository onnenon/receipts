defmodule Receipts.AI.CompSuggestion do
  @moduledoc false

  require Ash.Query

  alias Receipts.LoL.{CompPromptLabRun, CompSuggestionCache, Queries, Queue}

  @positions ~w(TOP JUNGLE MIDDLE BOTTOM UTILITY)
  @cache_ttl_seconds 86_400
  @default_temperature 0.25
  @default_system_instruction """
  You are helping a private League of Legends friend group choose roles and champions.
  Use only the supplied JSON. Recommend one primary position per player.
  Prefer meaningful evidence from shared games, then recent non-shared games, then overall games.
  When a player's shared-game champion pool has mostly low games_played samples, favor his
  recent non-shared champion and position results over weak shared champion samples.
  Be explicit about low sample sizes. Do not invent player history or champion stats.
  All players in this friend group are men; use he/him/his pronouns for every player.
  Write user-facing prose. Never include raw JSON path names, snake_case keys, or dotted
  references like recent_non_shared_positions.MIDDLE in the response.
  Each alternative must include a complete lineup with one slot for every selected player.
  """
  @default_prompt_template """
  Generate a comp suggestion for this selected group.

  Return JSON matching the schema. Use player_id values exactly as provided.
  Valid positions are TOP, JUNGLE, MIDDLE, BOTTOM, UTILITY.
  If shared_top_champions or shared position champion samples are thin for a player, lean on
  recent_non_shared_top_champions and recent_non_shared_positions for that player's role and
  champion recommendations, while calling out the small shared sample in the evidence or caveats.
  """
  @context_block_definitions [
    %{
      "key" => "shared_group_stats",
      "label" => "Shared group stats",
      "description" =>
        "Adds total shared games and aggregate group performance for games containing every selected player.",
      "schema" =>
        "shared_games: {count, group: {games, wins, losses, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score}}"
    },
    %{
      "key" => "player_accounts",
      "label" => "Player accounts and rank",
      "description" =>
        "Adds each player's Riot accounts, regions, and rank context so recommendations understand account coverage.",
      "schema" => "account: {game_name, tag_line, region, rank_tier, rank_division, rank_lp}"
    },
    %{
      "key" => "player_game_counts",
      "label" => "Player game counts",
      "description" =>
        "Adds all-game and shared-game counts for each player, useful for judging sample size.",
      "schema" => "player counts: {all_games, shared_games}"
    },
    %{
      "key" => "shared_position_stats",
      "label" => "Shared position stats",
      "description" =>
        "Adds per-player role performance from games this exact group played together.",
      "schema" =>
        "position summary: {position, label, games, wins, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score, top_champions}"
    },
    %{
      "key" => "recent_non_shared_position_stats",
      "label" => "Recent non-shared position stats",
      "description" =>
        "Adds recent individual role performance outside the selected shared games, currently capped at 40 games per player.",
      "schema" =>
        "position summary: {position, label, games, wins, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score, top_champions}"
    },
    %{
      "key" => "overall_position_stats",
      "label" => "Overall position stats",
      "description" => "Adds all-time role performance within the active queue and year filters.",
      "schema" =>
        "position summary: {position, label, games, wins, win_rate, avg_kills, avg_deaths, avg_assists, avg_cs, avg_damage_dealt, avg_vision_score, top_champions}"
    },
    %{
      "key" => "shared_top_champions",
      "label" => "Shared top champions",
      "description" =>
        "Adds each player's top champions from games this exact group played together.",
      "schema" =>
        "champion summary: {champion: {id, key, name}, games_played, wins, win_rate, avg_kills, avg_deaths, avg_assists, kda_ratio}"
    },
    %{
      "key" => "recent_non_shared_top_champions",
      "label" => "Recent non-shared top champions",
      "description" =>
        "Adds each player's recent individual champion results outside the selected shared games.",
      "schema" =>
        "champion summary: {champion: {id, key, name}, games_played, wins, win_rate, avg_kills, avg_deaths, avg_assists, kda_ratio}"
    },
    %{
      "key" => "overall_top_champions",
      "label" => "Overall top champions",
      "description" => "Adds each player's best champions across all matching games.",
      "schema" =>
        "champion summary: {champion: {id, key, name}, games_played, wins, win_rate, avg_kills, avg_deaths, avg_assists, kda_ratio}"
    },
    %{
      "key" => "position_definitions",
      "label" => "Position definitions",
      "description" => "Adds the legal League role keys and display labels the model may use.",
      "schema" => "position: {key, label}"
    },
    %{
      "key" => "interpretation_notes",
      "label" => "Interpretation notes",
      "description" =>
        "Adds guardrails explaining shared-game context, recent form, and small sample handling.",
      "schema" => "note: string"
    }
  ]

  def suggest(player_ids, opts \\ []) do
    with {:ok, context} <- Queries.comp_suggestion_context_for_players(player_ids, opts),
         {:ok, response} <-
           ai_client().generate_structured(prompt(context), response_schema(), ai_opts()) do
      {:ok, normalize_response(response, context)}
    end
  end

  def prompt_lab_defaults(player_ids, opts \\ []) do
    with {:ok, _context} <- Queries.comp_suggestion_context_for_players(player_ids, opts) do
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

    with {:ok, raw_context} <- Queries.comp_suggestion_context_for_players(player_ids, opts),
         context = apply_context_config(raw_context, context_config),
         context_json = encode_context(context),
         {:ok, response} <-
           ai_client().generate_structured(
             render_prompt_template(prompt_template, context_json),
             response_schema(),
             ai_opts(system_instruction: system_instruction, temperature: temperature)
           ),
         suggestion = normalize_response(response, context),
         {:ok, record} <-
           store_prompt_lab_run(player_ids, opts, %{
             system_instruction: system_instruction,
             prompt_template: prompt_template,
             context: context,
             context_config: context_config,
             temperature: temperature,
             suggestion: suggestion
           }) do
      {:ok, prompt_lab_result(record)}
    end
  end

  def rate_run(run_id, rating) when rating in 1..5 do
    with {:ok, record} <- Ash.get(CompPromptLabRun, run_id),
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

  defp store_prompt_lab_run(player_ids, opts, attrs) do
    CompPromptLabRun
    |> Ash.Changeset.for_create(:create, %{
      group_key: cache_key(player_ids, opts),
      player_ids: normalize_player_ids(player_ids),
      filters: cache_filters(opts),
      system_instruction: attrs.system_instruction,
      prompt_template: attrs.prompt_template,
      context: attrs.context,
      context_config: attrs.context_config,
      temperature: attrs.temperature,
      suggestion: attrs.suggestion,
      generated_at: DateTime.utc_now()
    })
    |> Ash.create()
  end

  defp prompt_lab_history_records(group_key) do
    CompPromptLabRun
    |> Ash.Query.filter(group_key == ^group_key)
    |> Ash.Query.sort(generated_at: :desc)
    |> Ash.Query.limit(10)
    |> Ash.read!()
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

  defp prompt_lab_result(record) do
    %{
      id: record.id,
      suggestion: clean_suggestion(record.suggestion),
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
    selected_players = selected_players_by_id(context)

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
      "mode" => "selected_comp_suggestion_context",
      "filters" => cache_filters(opts),
      "blocks" =>
        Enum.map(@context_block_definitions, fn block ->
          %{
            "key" => block["key"],
            "enabled" => MapSet.member?(selected_keys, block["key"]),
            "params" => default_context_block_params(block["key"])
          }
        end)
    }
  end

  defp default_context_config(opts) do
    %{
      "version" => 1,
      "mode" => "default_comp_suggestion_context",
      "filters" => cache_filters(opts),
      "blocks" =>
        Enum.map(@context_block_definitions, fn block ->
          %{
            "key" => block["key"],
            "enabled" => true,
            "params" => default_context_block_params(block["key"])
          }
        end)
    }
  end

  defp default_context_block_keys do
    Enum.map(@context_block_definitions, & &1["key"])
  end

  defp default_context_block_params("shared_position_stats"),
    do: %{"top_champion_limit_per_position" => 5}

  defp default_context_block_params("recent_non_shared_position_stats"),
    do: %{"match_limit_per_player" => 40, "top_champion_limit_per_position" => 5}

  defp default_context_block_params("overall_position_stats"),
    do: %{"top_champion_limit_per_position" => 5}

  defp default_context_block_params("shared_top_champions"), do: %{"limit" => 8}

  defp default_context_block_params("recent_non_shared_top_champions"),
    do: %{"match_limit_per_player" => 40, "limit" => 8}

  defp default_context_block_params("overall_top_champions"), do: %{"limit" => 10}
  defp default_context_block_params(_key), do: %{}

  defp apply_context_config(context, context_config) do
    enabled = enabled_context_blocks(context_config)

    %{
      filters: context.filters,
      selected_players: context.selected_players,
      players: Enum.map(context.players, &filter_player_context(&1, enabled))
    }
    |> maybe_put_context(:shared_games, context.shared_games, enabled, "shared_group_stats")
    |> maybe_put_context(:positions, context.positions, enabled, "position_definitions")
    |> maybe_put_context(:notes, context.notes, enabled, "interpretation_notes")
  end

  defp filter_player_context(player, enabled) do
    %{id: player.id, name: player.name}
    |> maybe_put_context(:accounts, player.accounts, enabled, "player_accounts")
    |> maybe_put_context(:all_games, player.all_games, enabled, "player_game_counts")
    |> maybe_put_context(:shared_games, player.shared_games, enabled, "player_game_counts")
    |> maybe_put_context(
      :shared_positions,
      player.shared_positions,
      enabled,
      "shared_position_stats"
    )
    |> maybe_put_context(
      :recent_non_shared_positions,
      player.recent_non_shared_positions,
      enabled,
      "recent_non_shared_position_stats"
    )
    |> maybe_put_context(
      :overall_positions,
      player.overall_positions,
      enabled,
      "overall_position_stats"
    )
    |> maybe_put_context(
      :shared_top_champions,
      player.shared_top_champions,
      enabled,
      "shared_top_champions"
    )
    |> maybe_put_context(
      :recent_non_shared_top_champions,
      player.recent_non_shared_top_champions,
      enabled,
      "recent_non_shared_top_champions"
    )
    |> maybe_put_context(
      :overall_top_champions,
      player.overall_top_champions,
      enabled,
      "overall_top_champions"
    )
  end

  defp maybe_put_context(context, key, value, enabled, block_key) do
    if MapSet.member?(enabled, block_key), do: Map.put(context, key, value), else: context
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

  defp selected_players_by_id(%{selected_players: selected_players}) do
    selected_players
    |> Enum.map(&{to_string(&1.id), &1.name})
    |> Map.new()
  end

  defp selected_players_by_id(%{"selected_players" => selected_players}) do
    selected_players
    |> Enum.map(&{to_string(Map.get(&1, "id")), Map.get(&1, "name", "")})
    |> Map.new()
  end

  defp selected_players_by_id(_context), do: %{}

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
