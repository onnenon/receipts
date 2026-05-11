defmodule ReceiptsWeb.CompPromptLabLive do
  use ReceiptsWeb, :live_view

  require Ash.Query
  require Logger

  alias Receipts.AI.CompSuggestion
  alias Receipts.LoL.{Player, Queue}

  @impl true
  def mount(params, _session, socket) do
    player_ids = player_ids_from_params(params)
    players = load_players(player_ids)

    if length(players) < 2 do
      {:ok, push_navigate(socket, to: ~p"/players")}
    else
      queue_types = queue_types_from_params(params, players)
      from_year = year_from_param(params["from_year"])
      to_year = year_from_param(params["to_year"])
      opts = [queue_types: queue_types, from_year: from_year, to_year: to_year]

      {:ok,
       socket
       |> assign(:players, players)
       |> assign(:player_ids, Enum.map(players, & &1.id))
       |> assign(:queue_types, queue_types)
       |> assign(:from_year, from_year)
       |> assign(:to_year, to_year)
       |> assign(:opts, opts)
       |> assign(:context_blocks, CompSuggestion.context_block_definitions())
       |> assign(:form, to_form(%{}, as: :prompt_lab))
       |> assign(:inputs, %{})
       |> assign(:result, nil)
       |> assign(:run_id, nil)
       |> assign(:generated_at, nil)
       |> assign(:error, nil)
       |> assign(:loading, false)
       |> load_defaults()
       |> load_history()}
    end
  end

  @impl true
  def handle_event("update", %{"prompt_lab" => params}, socket) do
    {:noreply, assign_inputs(socket, params)}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> load_defaults()
     |> assign(:result, nil)
     |> assign(:run_id, nil)
     |> assign(:generated_at, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("run", %{"prompt_lab" => params}, socket) do
    player_ids = socket.assigns.player_ids
    opts = socket.assigns.opts

    {:noreply,
     socket
     |> assign_inputs(params)
     |> assign(:result, nil)
     |> assign(:run_id, nil)
     |> assign(:generated_at, nil)
     |> assign(:error, nil)
     |> assign(:loading, true)
     |> start_async(:run_prompt_lab, fn ->
       CompSuggestion.trial_prompt(player_ids, opts, params)
     end)}
  end

  @impl true
  def handle_event("view_run", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.history, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      run ->
        inputs =
          stringify_inputs(%{
            system_instruction: run.system_instruction,
            prompt_template: run.prompt_template,
            context_config_json: Jason.encode!(run.context_config, pretty: true),
            context_blocks: selected_context_blocks(run.context_config),
            temperature: run.temperature
          })

        {:noreply,
         socket
         |> assign_inputs(inputs)
         |> assign_run(run)
         |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_async(:run_prompt_lab, {:ok, {:ok, run}}, socket) do
    {:noreply,
     socket
     |> assign_run(run)
     |> assign(:error, nil)
     |> assign(:loading, false)
     |> load_history()}
  end

  def handle_async(:run_prompt_lab, {:ok, {:error, reason}}, socket) do
    Logger.error("Comp prompt lab failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:error, error_message(reason))
     |> assign(:loading, false)}
  end

  def handle_async(:run_prompt_lab, {:exit, reason}, socket) do
    Logger.error("Comp prompt lab task exited: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:error, "Prompt lab run failed. Try again in a moment.")
     |> assign(:loading, false)}
  end

  defp load_defaults(socket) do
    case CompSuggestion.prompt_lab_defaults(socket.assigns.player_ids, socket.assigns.opts) do
      {:ok, defaults} ->
        assign_inputs(socket, defaults)

      {:error, reason} ->
        assign(socket, :error, error_message(reason))
    end
  end

  defp load_history(socket) do
    assign(
      socket,
      :history,
      CompSuggestion.prompt_lab_history(socket.assigns.player_ids, socket.assigns.opts)
    )
  end

  defp assign_inputs(socket, params) do
    inputs =
      socket.assigns.inputs
      |> Map.merge(stringify_inputs(params))

    socket
    |> assign(:inputs, inputs)
    |> assign(:form, to_form(inputs, as: :prompt_lab))
  end

  defp assign_run(socket, run) do
    socket
    |> assign(:result, run.suggestion)
    |> assign(:run_id, run.id)
    |> assign(:generated_at, run.generated_at)
  end

  defp stringify_inputs(values) do
    %{
      "system_instruction" =>
        to_string(
          Map.get(values, :system_instruction) || Map.get(values, "system_instruction") || ""
        ),
      "prompt_template" =>
        to_string(Map.get(values, :prompt_template) || Map.get(values, "prompt_template") || ""),
      "context_config_json" =>
        to_string(
          Map.get(values, :context_config_json) || Map.get(values, "context_config_json") || ""
        ),
      "context_blocks" => context_blocks_from_values(values),
      "temperature" =>
        to_string(Map.get(values, :temperature) || Map.get(values, "temperature") || "0.25")
    }
  end

  defp context_blocks_from_values(values) do
    cond do
      Map.has_key?(values, :context_blocks) ->
        normalize_context_blocks(Map.get(values, :context_blocks))

      Map.has_key?(values, "context_blocks") ->
        normalize_context_blocks(Map.get(values, "context_blocks"))

      true ->
        values
        |> Map.get(:context_config_json, Map.get(values, "context_config_json", ""))
        |> selected_context_blocks_from_json()
    end
  end

  defp selected_context_blocks_from_json("") do
    Enum.map(CompSuggestion.context_block_definitions(), & &1["key"])
  end

  defp selected_context_blocks_from_json(context_config_json) do
    case Jason.decode(context_config_json) do
      {:ok, context_config} -> selected_context_blocks(context_config)
      _ -> Enum.map(CompSuggestion.context_block_definitions(), & &1["key"])
    end
  end

  defp selected_context_blocks(%{"blocks" => blocks}) do
    blocks
    |> Enum.filter(&Map.get(&1, "enabled", false))
    |> Enum.map(&Map.get(&1, "key"))
    |> normalize_context_blocks()
  end

  defp selected_context_blocks(_context_config),
    do: Enum.map(CompSuggestion.context_block_definitions(), & &1["key"])

  defp normalize_context_blocks(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp player_ids_from_params(%{"ids" => ids}) do
    ids
    |> String.split(",", trim: true)
    |> Enum.uniq()
  end

  defp player_ids_from_params(_params), do: []

  defp load_players(player_ids) do
    players =
      Player
      |> Ash.Query.filter(id in ^player_ids)
      |> Ash.Query.load(:accounts)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})

    player_ids
    |> Enum.map(&Map.get(players, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp queue_types_from_params(%{"queues" => queues}, _players) when is_binary(queues) do
    queues
    |> String.split(",", trim: true)
    |> Enum.uniq()
  end

  defp queue_types_from_params(_params, players) when length(players) > 2, do: ["ranked_flex"]
  defp queue_types_from_params(_params, _players), do: Queue.default_queues()

  defp year_from_param(nil), do: nil
  defp year_from_param(""), do: nil

  defp year_from_param(value) do
    case Integer.parse(value) do
      {year, ""} -> year
      _ -> nil
    end
  end

  defp compare_path(assigns) do
    ~p"/players/compare?ids=#{Enum.join(assigns.player_ids, ",")}"
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y %-I:%M %p UTC")
  end

  defp format_datetime(_), do: ""

  defp confidence_badge_class("high"), do: "border-success/30 bg-success/10 text-success"
  defp confidence_badge_class("medium"), do: "border-warning/30 bg-warning/10 text-warning"
  defp confidence_badge_class(_), do: "border-base-300 bg-base-100 text-base-content/55"

  defp position_badge_class("TOP"), do: "bg-emerald-500/10 text-emerald-700 ring-emerald-500/25"
  defp position_badge_class("JUNGLE"), do: "bg-lime-500/10 text-lime-700 ring-lime-500/25"
  defp position_badge_class("MIDDLE"), do: "bg-sky-500/10 text-sky-700 ring-sky-500/25"
  defp position_badge_class("BOTTOM"), do: "bg-rose-500/10 text-rose-700 ring-rose-500/25"
  defp position_badge_class("UTILITY"), do: "bg-violet-500/10 text-violet-700 ring-violet-500/25"
  defp position_badge_class(_), do: "bg-base-300 text-base-content/60 ring-base-300"

  defp error_message({:invalid_context_json, _error}),
    do: "Context JSON is invalid. Fix the JSON and run again."

  defp error_message(:missing_api_key),
    do: "GEMINI_API_KEY is not configured for this environment."

  defp error_message(:not_enough_players), do: "Select at least two players."

  defp error_message(%Req.TransportError{reason: :timeout}),
    do: "Gemini timed out while running the prompt lab. Try again in a moment."

  defp error_message(_reason), do: "Prompt lab run failed. Try again in a moment."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} admin_authenticated={@admin_authenticated}>
      <div class="space-y-6">
        <div
          id="comp-prompt-lab-header"
          class="flex flex-col gap-4 rounded-xl border border-base-300 bg-base-200 p-5 sm:flex-row sm:items-start sm:justify-between"
        >
          <div>
            <p class="text-xs font-semibold uppercase tracking-widest text-primary">Comp Prompt Lab</p>
            <h1 class="mt-1 text-2xl font-bold tracking-tight">
              {Enum.map_join(@players, " + ", & &1.name)}
            </h1>
            <div class="mt-3 flex flex-wrap gap-2 text-xs font-semibold text-base-content/55">
              <span class="rounded-md border border-base-300 bg-base-100 px-2 py-1">
                Queues: {Enum.map_join(@queue_types, ", ", &Queue.label/1)}
              </span>
              <span :if={@from_year} class="rounded-md border border-base-300 bg-base-100 px-2 py-1">
                From {@from_year}
              </span>
              <span :if={@to_year} class="rounded-md border border-base-300 bg-base-100 px-2 py-1">
                To {@to_year}
              </span>
            </div>
          </div>
          <.link
            id="back-to-comparison"
            navigate={compare_path(assigns)}
            class="inline-flex items-center justify-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm font-bold text-base-content/65 transition hover:border-base-content/20 hover:text-base-content"
          >
            <.icon name="hero-arrow-left-mini" class="h-4 w-4" />
            Back
          </.link>
        </div>

        <section id="comp-prompt-lab" class="rounded-xl border border-base-300 bg-base-200 p-4">
          <.form
            for={@form}
            id="comp-prompt-lab-form"
            phx-change="update"
            phx-submit="run"
            class="space-y-4"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p class="text-sm font-bold text-base-content">Experiment</p>
                <p class="mt-1 text-xs leading-5 text-base-content/50">
                  Runs are saved as prompt experiments, separate from production comp suggestions.
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <button
                  id="reset-comp-prompt-lab"
                  type="button"
                  phx-click="reset"
                  class="inline-flex items-center justify-center gap-2 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm font-bold text-base-content/65 transition hover:border-base-content/20 hover:text-base-content"
                >
                  <.icon name="hero-arrow-uturn-left-mini" class="h-4 w-4" />
                  Reset
                </button>
                <button
                  id="run-comp-prompt-lab"
                  type="submit"
                  disabled={@loading}
                  class="inline-flex min-w-28 items-center justify-center gap-2 rounded-lg bg-secondary px-3 py-2 text-sm font-bold text-secondary-content shadow-sm transition hover:bg-secondary/90 disabled:cursor-wait disabled:opacity-65"
                >
                  <%= if @loading do %>
                    <.icon name="hero-arrow-path-mini" class="h-4 w-4 animate-spin" />
                    Running...
                  <% else %>
                    <.icon name="hero-play-mini" class="h-4 w-4" />
                    Run Test
                  <% end %>
                </button>
              </div>
            </div>

            <div class="grid gap-4 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
              <div class="space-y-3">
                <.input
                  field={@form[:system_instruction]}
                  type="textarea"
                  label="System instruction"
                  rows="9"
                  class="min-h-52 w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 font-mono text-xs leading-5 text-base-content/80 shadow-sm focus:border-primary focus:outline-none"
                />
                <.input
                  field={@form[:prompt_template]}
                  type="textarea"
                  label="User prompt template"
                  rows="9"
                  class="min-h-52 w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 font-mono text-xs leading-5 text-base-content/80 shadow-sm focus:border-primary focus:outline-none"
                />
                <.input
                  field={@form[:temperature]}
                  type="number"
                  label="Temperature"
                  min="0"
                  max="2"
                  step="0.05"
                  placeholder="0.25"
                  class="w-32 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm focus:border-primary focus:outline-none"
                />
                <div
                  id="temperature-help"
                  class="rounded-lg border border-base-300 bg-base-100/70 px-3 py-2 text-xs leading-5 text-base-content/55"
                >
                  Default: 0.25. Temperature controls how much variation Gemini is allowed to use.
                  Lower values make runs more consistent and literal; higher values can explore more
                  wording and lineup alternatives, but make prompt comparisons noisier.
                </div>
              </div>

              <div class="space-y-3">
                <div
                  id="context-block-help"
                  class="rounded-lg border border-base-300 bg-base-100/70 px-3 py-3 text-xs leading-5 text-base-content/55"
                >
                  <p class="font-bold text-base-content/70">Context included in this run</p>
                  <p class="mt-1">
                    Filters, selected player IDs, and player names are always included. The checked
                    blocks below run server-side data builders and are serialized with each saved
                    experiment so a good setup can be promoted into production later.
                  </p>
                </div>

                <input type="hidden" name="prompt_lab[context_blocks][]" value="" />

                <div id="context-blocks" class="grid gap-2">
                  <%= for block <- @context_blocks do %>
                    <label
                      id={"context-block-#{block["key"]}"}
                      class="flex gap-3 rounded-lg border border-base-300 bg-base-100/70 px-3 py-3 transition hover:border-base-content/20"
                    >
                      <input
                        type="checkbox"
                        name="prompt_lab[context_blocks][]"
                        value={block["key"]}
                        checked={block["key"] in @inputs["context_blocks"]}
                        class="mt-1 checkbox checkbox-sm"
                      />
                      <span class="min-w-0">
                        <span class="block text-sm font-bold text-base-content/80">
                          {block["label"]}
                        </span>
                        <span class="mt-1 block text-xs leading-5 text-base-content/50">
                          {block["description"]}
                        </span>
                      </span>
                    </label>
                  <% end %>
                </div>

                <input
                  type="hidden"
                  id="prompt_lab_context_config_json"
                  name="prompt_lab[context_config_json]"
                  value={@inputs["context_config_json"]}
                />
              </div>
            </div>
          </.form>

          <div
            :if={@error}
            id="comp-prompt-lab-error"
            class="mt-3 rounded-lg border border-error/30 bg-error/10 px-3 py-2 text-sm text-error"
          >
            {@error}
          </div>
        </section>

        <section
          :if={@result}
          id="comp-prompt-lab-result"
          class="rounded-xl border border-secondary/30 bg-secondary/10 p-4"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-secondary">Test Result</p>
              <p class="mt-1 max-w-3xl text-sm leading-6 text-base-content/75">
                {@result["summary"]}
              </p>
              <p :if={@generated_at} id="comp-prompt-lab-generated-at" class="mt-1 text-xs text-base-content/40">
                Saved {format_datetime(@generated_at)}
              </p>
            </div>
            <span class={[
              "inline-flex shrink-0 items-center rounded-lg border px-2.5 py-1 text-xs font-bold capitalize",
              confidence_badge_class(@result["confidence"])
            ]}>
              {@result["confidence"]} confidence
            </span>
          </div>

          <div class="mt-3 grid gap-2 md:grid-cols-2 xl:grid-cols-3">
            <%= for slot <- @result["recommended_lineup"] do %>
              <div
                id={"comp-prompt-lab-slot-#{slot["player_id"]}"}
                class="rounded-lg border border-base-300 bg-base-100/70 p-3"
              >
                <div class="flex items-center justify-between gap-2">
                  <p class="truncate text-sm font-bold">{slot["player_name"]}</p>
                  <span class={[
                    "shrink-0 rounded px-1.5 py-px text-xs font-bold ring-1",
                    position_badge_class(slot["position"])
                  ]}>
                    {slot["position_label"]}
                  </span>
                </div>
                <p class="mt-2 text-xs leading-5 text-base-content/60">{slot["reason"]}</p>
              </div>
            <% end %>
          </div>
        </section>

        <section
          :if={@history != []}
          id="comp-prompt-lab-history"
          class="rounded-xl border border-base-300 bg-base-200 p-4"
        >
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Saved Experiments
          </p>
          <div class="mt-2 grid gap-2 md:grid-cols-2 xl:grid-cols-3">
            <%= for run <- @history do %>
              <button
                id={"view-comp-prompt-lab-run-#{run.id}"}
                type="button"
                phx-click="view_run"
                phx-value-id={run.id}
                class={[
                  "rounded-lg border px-3 py-2 text-left transition hover:border-secondary/50 hover:bg-base-100",
                  if(@run_id == run.id,
                    do: "border-secondary/50 bg-secondary/10",
                    else: "border-base-300 bg-base-100/50"
                  )
                ]}
              >
                <span class="flex items-center justify-between gap-2">
                  <span class="text-xs font-bold text-base-content/70">
                    {format_datetime(run.generated_at)}
                  </span>
                  <span class="text-xs font-semibold text-base-content/40">temp {run.temperature}</span>
                </span>
                <span class="mt-1 line-clamp-2 block text-xs leading-5 text-base-content/45">
                  {run.suggestion["summary"]}
                </span>
              </button>
            <% end %>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
