defmodule ReceiptsWeb.ReceiptsLive do
  use ReceiptsWeb, :live_view

  alias Receipts.LoL.{Player, Champion, Queue}
  alias Receipts.LoL.Queries

  @current_year 2026
  @earliest_year 2013

  @impl true
  def mount(params, _session, socket) do
    players = Ash.read!(Player)
    champions = Ash.read!(Champion) |> Enum.sort_by(& &1.name)

    {:ok,
     socket
     |> assign(:players, players)
     |> assign(:champions, champions)
     |> assign(:enabled_queues, MapSet.new(Queue.default_queues()))
     |> assign(:from_year, nil)
     |> assign(:to_year, nil)
     |> assign(:search_player_id, params["player_id"])
     |> assign(:search_champion_key, nil)
     |> assign(:result, nil)
     |> assign(:result_player, nil)
     |> assign(:search_form, build_search_form(params["player_id"], nil))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    player_id = params["player_id"]

    {:noreply,
     assign(socket, search_player_id: player_id, search_form: build_search_form(player_id, nil))}
  end

  @impl true
  def handle_event(
        "search",
        %{"receipts" => %{"player_id" => player_id, "champion_key" => champion_key}},
        socket
      )
      when player_id != "" and champion_key != "" do
    socket =
      socket
      |> assign(:search_player_id, player_id)
      |> assign(:search_champion_key, champion_key)

    {:noreply, run_query(socket)}
  end

  def handle_event("search", _, socket) do
    {:noreply, put_flash(socket, :error, "Select a player and champion.")}
  end

  @impl true
  def handle_event("toggle_queue", %{"queue" => queue}, socket) do
    enabled =
      if MapSet.member?(socket.assigns.enabled_queues, queue),
        do: MapSet.delete(socket.assigns.enabled_queues, queue),
        else: MapSet.put(socket.assigns.enabled_queues, queue)

    socket = assign(socket, :enabled_queues, enabled)
    {:noreply, maybe_rerun(socket)}
  end

  @impl true
  def handle_event("update_years", %{"from_year" => from, "to_year" => to}, socket) do
    from_year = if from == "", do: nil, else: String.to_integer(from)
    to_year = if to == "", do: nil, else: String.to_integer(to)
    socket = socket |> assign(:from_year, from_year) |> assign(:to_year, to_year)
    {:noreply, maybe_rerun(socket)}
  end

  defp maybe_rerun(%{assigns: %{search_player_id: pid, search_champion_key: ck}} = socket)
       when is_binary(pid) and is_binary(ck) do
    run_query(socket)
  end

  defp maybe_rerun(socket), do: socket

  defp run_query(socket) do
    %{
      search_player_id: player_id,
      search_champion_key: champion_key,
      enabled_queues: enabled_queues,
      from_year: from_year,
      to_year: to_year,
      players: players
    } = socket.assigns

    opts = [
      queue_types: MapSet.to_list(enabled_queues),
      from_year: from_year,
      to_year: to_year
    ]

    case Queries.receipts(player_id, champion_key, opts) do
      {:ok, result} ->
        player = Enum.find(players, &(&1.id == player_id))
        socket |> assign(:result, result) |> assign(:result_player, player)

      {:error, :champion_not_found} ->
        socket |> assign(:result, nil) |> put_flash(:error, "Champion not found.")
    end
  end

  defp build_search_form(player_id, champion_key) do
    to_form(%{"player_id" => player_id || "", "champion_key" => champion_key || ""},
      as: "receipts"
    )
  end

  defp champion_icon_url(champion) do
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/#{champion.riot_id}.png"
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = dt) do
    "#{dt.month}/#{dt.day}/#{dt.year}"
  end

  defp win_rate_color(rate) when rate >= 55.0, do: "text-success"
  defp win_rate_color(rate) when rate < 45.0, do: "text-error"
  defp win_rate_color(_), do: "text-base-content"

  defp year_options do
    for year <- @earliest_year..@current_year//1, do: {to_string(year), year}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :queue_defs, Queue.ui_queues())

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Check Receipts</h1>
          <p class="mt-1 text-sm text-base-content/50">See the stats. Show the receipts.</p>
        </div>

        <%!-- Main search form --%>
        <.form for={@search_form} id="receipts-search-form" phx-submit="search">
          <div class="flex flex-wrap gap-3 items-end">
            <div class="flex-1 min-w-40">
              <.input
                field={@search_form[:player_id]}
                type="select"
                label="Player"
                options={[{"— select —", ""} | Enum.map(@players, &{&1.name, &1.id})]}
              />
            </div>
            <div class="flex-1 min-w-52">
              <.input
                field={@search_form[:champion_key]}
                type="select"
                label="Champion"
                options={[{"— select —", ""} | Enum.map(@champions, &{&1.name, &1.key})]}
              />
            </div>
            <button
              type="submit"
              class="rounded-lg bg-primary px-5 py-2 text-sm font-semibold text-primary-content hover:opacity-90 transition-opacity mb-1"
            >
              Check
            </button>
          </div>
        </.form>

        <%!-- Filters --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-4 space-y-4">
          <%!-- Queue toggles --%>
          <div>
            <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/50">Queue Types</p>
            <div class="flex flex-wrap gap-2">
              <%= for {queue_type, label, _default} <- @queue_defs do %>
                <button
                  id={"queue-toggle-#{queue_type}"}
                  phx-click="toggle_queue"
                  phx-value-queue={queue_type}
                  class={[
                    "rounded-full px-3 py-1 text-xs font-medium border transition-colors",
                    if(MapSet.member?(@enabled_queues, queue_type),
                      do: "bg-primary text-primary-content border-primary",
                      else: "border-base-300 text-base-content/50 hover:border-base-content/30 hover:text-base-content/70"
                    )
                  ]}
                >
                  {label}
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Year range --%>
          <form id="year-filter-form" phx-change="update_years">
            <div class="flex flex-wrap gap-4 items-end">
              <div>
                <p class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50">From Year</p>
                <select
                  id="from-year-select"
                  name="from_year"
                  class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-sm focus:outline-none focus:border-primary"
                >
                  <option value="">All time</option>
                  <%= for {label, year} <- Enum.reverse(year_options()) do %>
                    <option value={year} selected={@from_year == year}>{label}</option>
                  <% end %>
                </select>
              </div>
              <div>
                <p class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50">To Year</p>
                <select
                  id="to-year-select"
                  name="to_year"
                  class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-sm focus:outline-none focus:border-primary"
                >
                  <option value="">Now</option>
                  <%= for {label, year} <- Enum.reverse(year_options()) do %>
                    <option value={year} selected={@to_year == year}>{label}</option>
                  <% end %>
                </select>
              </div>
            </div>
          </form>
        </div>

        <%!-- Results --%>
        <%= if @result do %>
          <div id="receipts-result" class="space-y-6">
            <%!-- Champion header --%>
            <div class="flex items-center gap-4 rounded-xl border border-base-300 bg-base-200 p-5">
              <img
                src={champion_icon_url(@result.champion)}
                alt={@result.champion.name}
                class="h-16 w-16 rounded-full border-2 border-base-300 object-cover"
                onerror="this.style.display='none'"
              />
              <div>
                <p class="text-xs font-medium uppercase tracking-wide text-base-content/40">
                  {@result_player && @result_player.name} on
                </p>
                <h2 class="text-2xl font-bold">{@result.champion.name}</h2>
                <%= if @result.games_played == 0 do %>
                  <p class="text-sm text-base-content/50 mt-1">No games on record for the selected filters</p>
                <% end %>
              </div>
            </div>

            <%= if @result.games_played > 0 do %>
              <%!-- Stats grid --%>
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center">
                  <p class="text-3xl font-bold">{@result.games_played}</p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">Games</p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center">
                  <p class={["text-3xl font-bold", win_rate_color(@result.win_rate)]}>
                    {@result.win_rate}%
                  </p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">Win Rate</p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center">
                  <p class="text-3xl font-bold">
                    {@result.avg_kills}/{@result.avg_deaths}/{@result.avg_assists}
                  </p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
                    KDA · {@result.kda_ratio}:1
                  </p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center">
                  <p class="text-3xl font-bold">{@result.avg_cs}</p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">Avg CS</p>
                </div>
              </div>

              <%!-- Recent games --%>
              <div class="space-y-2">
                <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Recent Games
                </h3>
                <div class="rounded-xl border border-base-300 bg-base-200 divide-y divide-base-300">
                  <%= for game <- @result.recent_games do %>
                    <div class="flex items-center gap-3 px-4 py-3">
                      <div class={[
                        "w-12 shrink-0 rounded text-center py-0.5 text-xs font-bold",
                        if(game.win, do: "bg-success/20 text-success", else: "bg-error/20 text-error")
                      ]}>
                        {if game.win, do: "WIN", else: "LOSS"}
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold">
                          {game.kills}/{game.deaths}/{game.assists}
                          <span class="text-base-content/40 font-normal">·</span>
                          {game.cs} CS
                          <%= if game.position && game.position != "" do %>
                            <span class="text-base-content/40 font-normal">·</span>
                            {game.position}
                          <% end %>
                        </p>
                        <p class="text-xs text-base-content/40">
                          {Queue.label(game.match.queue_type)}
                        </p>
                      </div>
                      <div class="text-right shrink-0">
                        <p class="text-xs text-base-content/50">
                          {format_duration(game.match.game_duration_seconds)}
                        </p>
                        <p class="text-xs text-base-content/40">
                          {format_date(game.match.game_datetime)}
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
