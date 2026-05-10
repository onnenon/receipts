defmodule ReceiptsWeb.PlayerLive do
  use ReceiptsWeb, :live_view

  require Ash.Query

  alias Receipts.LoL.{Player, Champion, Queue}
  alias Receipts.LoL.Queries

  @current_year 2026
  @earliest_year 2013

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    player =
      Player
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.load([:accounts, :oldest_game_date, :newest_game_date])
      |> Ash.read!()
      |> List.first()

    case player do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/")}

      player ->
        all_champions = Ash.read!(Champion) |> Enum.sort_by(& &1.name)
        enabled_queues = MapSet.new(Queue.default_queues())

        top_champions =
          Queries.top_champions_for_player(player.id,
            queue_types: MapSet.to_list(enabled_queues)
          )

        {:ok,
         socket
         |> assign(:player, player)
         |> assign(:all_champions, all_champions)
         |> assign(:top_champions, top_champions)
         |> assign(:enabled_queues, enabled_queues)
         |> assign(:from_year, nil)
         |> assign(:to_year, nil)
         |> assign(:selected_champion, nil)
         |> assign(:champion_filter, "")
         |> assign(:champion_sort, :games)
         |> assign(:champion_limit, nil)
         |> assign(:filters_open, true)
         |> assign(:champions_open, true)
         |> assign(:result, nil)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params["champion"] do
      nil ->
        {:noreply, socket |> assign(:selected_champion, nil) |> assign(:result, nil)}

      champion_key ->
        case find_champion(socket.assigns.all_champions, champion_key) do
          nil ->
            {:noreply, socket}

          champion ->
            socket =
              socket
              |> assign(:selected_champion, champion)

            {:noreply, run_query(socket)}
        end
    end
  end

  @impl true
  def handle_event("select_champion", %{"key" => champion_key}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/players/#{socket.assigns.player.id}?champion=#{champion_key}")}
  end

  @impl true
  def handle_event("filter_champions", %{"champion" => query}, socket) do
    {:noreply, assign(socket, :champion_filter, query)}
  end

  @impl true
  def handle_event("toggle_filters", _, socket) do
    {:noreply, assign(socket, :filters_open, !socket.assigns.filters_open)}
  end

  @impl true
  def handle_event("toggle_champions", _, socket) do
    {:noreply, assign(socket, :champions_open, !socket.assigns.champions_open)}
  end

  @impl true
  def handle_event("set_champion_sort", %{"by" => by}, socket) do
    sort = if by == "win_rate", do: :win_rate, else: :games
    {:noreply, assign(socket, :champion_sort, sort)}
  end

  @impl true
  def handle_event("set_champion_limit", %{"n" => n}, socket) do
    limit = if n == "all", do: nil, else: String.to_integer(n)
    {:noreply, assign(socket, :champion_limit, limit)}
  end

  @impl true
  def handle_event("toggle_queue", %{"queue" => queue}, socket) do
    enabled =
      if MapSet.member?(socket.assigns.enabled_queues, queue),
        do: MapSet.delete(socket.assigns.enabled_queues, queue),
        else: MapSet.put(socket.assigns.enabled_queues, queue)

    {:noreply, socket |> assign(:enabled_queues, enabled) |> maybe_rerun()}
  end

  @impl true
  def handle_event("select_all_queues", _, socket) do
    enabled =
      Queue.ui_queues()
      |> Enum.map(fn {queue_type, _label, _default} -> queue_type end)
      |> MapSet.new()

    {:noreply, socket |> assign(:enabled_queues, enabled) |> maybe_rerun()}
  end

  @impl true
  def handle_event("clear_queues", _, socket) do
    {:noreply, socket |> assign(:enabled_queues, MapSet.new()) |> maybe_rerun()}
  end

  @impl true
  def handle_event("update_years", %{"from_year" => from, "to_year" => to}, socket) do
    from_year = if from == "", do: nil, else: String.to_integer(from)
    to_year = if to == "", do: nil, else: String.to_integer(to)

    {:noreply,
     socket |> assign(:from_year, from_year) |> assign(:to_year, to_year) |> maybe_rerun()}
  end

  defp maybe_rerun(socket) do
    socket = refresh_top_champions(socket)
    if socket.assigns.selected_champion, do: run_query(socket), else: socket
  end

  defp refresh_top_champions(socket) do
    %{player: player, enabled_queues: eq, from_year: from_year, to_year: to_year} = socket.assigns

    top_champions =
      Queries.top_champions_for_player(player.id,
        queue_types: MapSet.to_list(eq),
        from_year: from_year,
        to_year: to_year
      )

    assign(socket, :top_champions, top_champions)
  end

  defp run_query(socket) do
    %{
      player: player,
      selected_champion: champion,
      enabled_queues: eq,
      from_year: from_year,
      to_year: to_year
    } = socket.assigns

    opts = [queue_types: MapSet.to_list(eq), from_year: from_year, to_year: to_year]

    case Queries.receipts(player.id, champion.key, opts) do
      {:ok, result} ->
        assign(socket, :result, result)

      {:error, :champion_not_found} ->
        socket |> assign(:result, nil) |> put_flash(:error, "Champion not found.")
    end
  end

  @tier_order ~w(IRON BRONZE SILVER GOLD PLATINUM EMERALD DIAMOND MASTER GRANDMASTER CHALLENGER)
  @division_order ~w(IV III II I)

  defp rank_score(nil, _), do: -1

  defp rank_score(tier, division) do
    tier_idx = Enum.find_index(@tier_order, &(&1 == tier)) || -1
    div_idx = Enum.find_index(@division_order, &(&1 == division)) || 0
    tier_idx * 4 + div_idx
  end

  defp best_rank(accounts) do
    accounts
    |> Enum.filter(& &1.rank_tier)
    |> Enum.max_by(fn acc -> rank_score(acc.rank_tier, acc.rank_division) end, fn -> nil end)
  end

  defp rank_label(%{rank_tier: tier, rank_division: _div})
       when tier in ~w(MASTER GRANDMASTER CHALLENGER) do
    String.capitalize(String.downcase(tier))
  end

  defp rank_label(%{rank_tier: tier, rank_division: div}) when not is_nil(tier) do
    "#{String.capitalize(String.downcase(tier))} #{div}"
  end

  defp rank_label(_), do: nil

  defp rank_icon_url(%{rank_tier: tier}) when not is_nil(tier) do
    "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/ranked-emblem/emblem-#{String.downcase(tier)}.png"
  end

  defp rank_icon_url(_), do: nil

  @opgg_regions %{
    "na1" => "na",
    "euw1" => "euw",
    "kr" => "kr",
    "eun1" => "eune",
    "br1" => "br",
    "oc1" => "oce",
    "jp1" => "jp",
    "tr1" => "tr",
    "la1" => "lan",
    "la2" => "las",
    "ru" => "ru"
  }

  defp opgg_url(%{riot_region: region, riot_game_name: name, riot_tag_line: tag}) do
    slug = Map.get(@opgg_regions, region, region)
    encoded = URI.encode("#{name}-#{tag}")
    "https://www.op.gg/summoners/#{slug}/#{encoded}"
  end

  defp filter_champions_by_name(champions, ""), do: champions

  defp filter_champions_by_name(champions, query) do
    normalized = String.downcase(query)
    Enum.filter(champions, &String.contains?(String.downcase(&1.champion.name), normalized))
  end

  defp apply_sort_and_limit(top_champions, sort_by, limit) do
    sorted =
      case sort_by do
        :win_rate -> Enum.sort_by(top_champions, &{-&1.win_rate, -&1.games_played})
        _ -> top_champions
      end

    case limit do
      nil -> sorted
      n -> Enum.take(sorted, n)
    end
  end

  defp find_champion(champions, query) do
    normalized = normalize_champion(query)

    Enum.find(champions, fn c ->
      normalize_champion(c.name) == normalized || normalize_champion(c.key) == normalized
    end)
  end

  defp normalize_champion(value) do
    value |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
  end

  defp champion_icon_url(champion) do
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/#{champion.riot_id}.png"
  end

  defp win_rate_color(rate) when rate >= 55.0, do: "text-success"
  defp win_rate_color(rate) when rate < 45.0, do: "text-error"
  defp win_rate_color(_), do: "text-base-content"

  defp win_rate_bg(rate) when rate >= 55.0, do: "bg-success/15 text-success border-success/30"
  defp win_rate_bg(rate) when rate < 45.0, do: "bg-error/15 text-error border-error/30"
  defp win_rate_bg(_), do: "bg-base-300/50 text-base-content/70 border-base-300"

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = dt), do: "#{dt.month}/#{dt.day}/#{dt.year}"

  defp year_options do
    for year <- @earliest_year..@current_year//1, do: {to_string(year), year}
  end

  defp total_games(top_champions), do: Enum.sum(Enum.map(top_champions, & &1.games_played))

  defp overall_win_rate([]), do: 0.0

  defp overall_win_rate(top_champions) do
    total = Enum.sum(Enum.map(top_champions, & &1.games_played))
    wins = Enum.sum(Enum.map(top_champions, & &1.wins))
    if total > 0, do: Float.round(wins / total * 100, 1), else: 0.0
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:queue_defs, Queue.ui_queues())
      |> assign(:total_games, total_games(assigns.top_champions))
      |> assign(:overall_wr, overall_win_rate(assigns.top_champions))
      |> assign(
        :displayed_champions,
        assigns.top_champions
        |> filter_champions_by_name(assigns.champion_filter)
        |> apply_sort_and_limit(assigns.champion_sort, assigns.champion_limit)
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-start gap-3">
          <.link
            navigate={~p"/"}
            class="mt-1 rounded-lg p-1.5 text-base-content/50 transition hover:bg-base-200 hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="h-5 w-5" />
          </.link>
          <% best = best_rank(@player.accounts) %>
          <div class="min-w-0 flex-1">
            <p class="text-xs font-semibold uppercase tracking-wide text-primary">Receipts</p>
            <div class="flex flex-wrap items-center gap-3">
              <h1 class="text-3xl font-bold tracking-tight">{@player.name}</h1>
              <%= if best do %>
                <div class="flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-200 px-2.5 py-1">
                  <img
                    src={rank_icon_url(best)}
                    alt={rank_label(best)}
                    class="h-5 w-5 object-contain"
                    onerror="this.style.display='none'"
                  />
                  <span class="text-sm font-semibold">{rank_label(best)}</span>
                  <span class="text-xs text-base-content/40">{best.rank_lp} LP</span>
                </div>
              <% end %>
            </div>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1">
              <%= if @total_games > 0 do %>
                <span class="text-sm text-base-content/55">{@total_games} games tracked</span>
                <span class={["text-sm font-semibold", win_rate_color(@overall_wr)]}>
                  {@overall_wr}% overall WR
                </span>
                <%= if @player.oldest_game_date do %>
                  <span class="text-sm text-base-content/40">
                    since {Calendar.strftime(@player.oldest_game_date, "%b %Y")}
                  </span>
                <% end %>
              <% end %>
              <%= for account <- @player.accounts do %>
                <a
                  href={opgg_url(account)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-1 rounded-md border border-base-300 bg-base-200 px-2 py-0.5 text-xs font-medium text-base-content/60 transition hover:border-base-content/30 hover:text-base-content"
                >
                  {account.riot_game_name}#{account.riot_tag_line}
                  <.icon name="hero-arrow-top-right-on-square-mini" class="h-3 w-3" />
                </a>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Filters (collapsible) --%>
        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
          <button
            id="toggle-filters-btn"
            phx-click="toggle_filters"
            class="flex w-full items-center justify-between px-4 py-3 text-left transition hover:bg-base-300/40"
          >
            <div>
              <p class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                Filters
              </p>
              <p class="text-xs text-base-content/40">
                {MapSet.size(@enabled_queues)} queues
                <%= if @from_year || @to_year do %>
                  · {if @from_year, do: @from_year, else: "all"} – {if @to_year, do: @to_year, else: "now"}
                <% else %>
                  · all time
                <% end %>
              </p>
            </div>
            <.icon
              name={if @filters_open, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
              class="h-4 w-4 shrink-0 text-base-content/40"
            />
          </button>

          <%= if @filters_open do %>
            <div class="space-y-4 border-t border-base-300 px-4 pb-4 pt-3">
              <div>
                <div class="mb-2 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    Game Types
                  </p>
                  <div class="flex gap-2">
                    <button
                      id="select-all-queues"
                      type="button"
                      phx-click="select_all_queues"
                      class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold transition hover:bg-base-300"
                    >
                      Select all
                    </button>
                    <button
                      id="clear-queues"
                      type="button"
                      phx-click="clear_queues"
                      class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold transition hover:bg-base-300"
                    >
                      Deselect all
                    </button>
                  </div>
                </div>
                <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                  <%= for {queue_type, label, _default} <- @queue_defs do %>
                    <button
                      id={"queue-toggle-#{queue_type}"}
                      phx-click="toggle_queue"
                      phx-value-queue={queue_type}
                      class={[
                        "rounded-lg px-3 py-2 text-left text-xs font-semibold border transition-colors",
                        if(MapSet.member?(@enabled_queues, queue_type),
                          do: "bg-primary text-primary-content border-primary",
                          else:
                            "border-base-300 text-base-content/50 hover:border-base-content/30 hover:text-base-content/70"
                        )
                      ]}
                    >
                      {label}
                    </button>
                  <% end %>
                </div>
              </div>

              <form id="year-filter-form" phx-change="update_years">
                <div class="flex flex-wrap items-end gap-4">
                  <div>
                    <p class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50">
                      From Year
                    </p>
                    <select
                      id="from-year-select"
                      name="from_year"
                      class="rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm focus:border-primary focus:outline-none"
                    >
                      <option value="">All time</option>
                      <%= for {label, year} <- Enum.reverse(year_options()) do %>
                        <option value={year} selected={@from_year == year}>{label}</option>
                      <% end %>
                    </select>
                  </div>
                  <div>
                    <p class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50">
                      To Year
                    </p>
                    <select
                      id="to-year-select"
                      name="to_year"
                      class="rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm focus:border-primary focus:outline-none"
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
          <% end %>
        </div>

        <%!-- Champion roster (collapsible) --%>
        <div class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
          <div class="flex items-center gap-3 px-4 py-3">
            <button
              id="toggle-champions-btn"
              phx-click="toggle_champions"
              class="flex items-center gap-2 text-left transition hover:opacity-80"
            >
              <div>
                <p class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Champions
                </p>
                <p class="text-xs text-base-content/40">
                  {length(@top_champions)} played · click to view receipts
                </p>
              </div>
              <.icon
                name={
                  if @champions_open, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"
                }
                class="h-4 w-4 shrink-0 text-base-content/40"
              />
            </button>

            <div class="flex-1" />

            <form id="champion-search-form" phx-change="filter_champions">
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass-mini"
                  class="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-base-content/40"
                />
                <input
                  id="champion-search-input"
                  type="search"
                  name="champion"
                  value={@champion_filter}
                  placeholder="Filter champions…"
                  autocomplete="off"
                  class="rounded-lg border border-base-300 bg-base-100 py-2 pl-8 pr-3 text-sm focus:border-primary focus:outline-none"
                />
              </div>
            </form>
          </div>

          <%= if @champions_open do %>
            <div class="border-t border-base-300 px-4 pb-4 pt-3">
              <%= if @top_champions == [] do %>
                <div class="py-8 text-center text-base-content/40">
                  <.icon name="hero-chart-bar" class="mx-auto h-8 w-8 mb-2" />
                  <p class="text-sm">No games synced yet.</p>
                </div>
              <% else %>
                <%!-- Sort + limit controls --%>
                <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <div class="flex items-center gap-1.5">
                    <span class="text-xs text-base-content/40 mr-1">Sort</span>
                    <button
                      id="sort-by-games"
                      phx-click="set_champion_sort"
                      phx-value-by="games"
                      class={[
                        "rounded-md border px-2.5 py-1 text-xs font-semibold transition-colors",
                        if(@champion_sort == :games,
                          do: "border-primary bg-primary text-primary-content",
                          else:
                            "border-base-300 bg-base-100 text-base-content/60 hover:border-base-content/30"
                        )
                      ]}
                    >
                      Games
                    </button>
                    <button
                      id="sort-by-winrate"
                      phx-click="set_champion_sort"
                      phx-value-by="win_rate"
                      class={[
                        "rounded-md border px-2.5 py-1 text-xs font-semibold transition-colors",
                        if(@champion_sort == :win_rate,
                          do: "border-primary bg-primary text-primary-content",
                          else:
                            "border-base-300 bg-base-100 text-base-content/60 hover:border-base-content/30"
                        )
                      ]}
                    >
                      Win Rate
                    </button>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-xs text-base-content/40 mr-1">Show</span>
                    <%= for {label, n} <- [{"10", 10}, {"25", 25}, {"All", nil}] do %>
                      <button
                        id={"limit-#{label}"}
                        phx-click="set_champion_limit"
                        phx-value-n={if n, do: n, else: "all"}
                        class={[
                          "rounded-md border px-2.5 py-1 text-xs font-semibold transition-colors",
                          if(@champion_limit == n,
                            do: "border-primary bg-primary text-primary-content",
                            else:
                              "border-base-300 bg-base-100 text-base-content/60 hover:border-base-content/30"
                          )
                        ]}
                      >
                        {label}
                      </button>
                    <% end %>
                  </div>
                </div>

                <div class="grid grid-cols-4 gap-2 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10">
                  <%= for champ_stat <- @displayed_champions do %>
                    <button
                      id={"champ-tile-#{champ_stat.champion.key}"}
                      phx-click="select_champion"
                      phx-value-key={champ_stat.champion.key}
                      class={[
                        "flex flex-col overflow-hidden rounded-xl border text-center transition-all duration-150",
                        if(@selected_champion && @selected_champion.id == champ_stat.champion.id,
                          do: "border-primary shadow-md ring-1 ring-primary/40",
                          else: "border-base-300 bg-base-100 hover:border-primary/50 hover:shadow-sm"
                        )
                      ]}
                    >
                      <img
                        src={champion_icon_url(champ_stat.champion)}
                        alt={champ_stat.champion.name}
                        class="w-full aspect-square object-cover"
                        onerror="this.style.display='none'"
                      />
                      <div class={[
                        "flex flex-col items-center gap-1 px-1.5 py-2",
                        if(@selected_champion && @selected_champion.id == champ_stat.champion.id,
                          do: "bg-primary/10",
                          else: "bg-base-100"
                        )
                      ]}>
                        <p class="w-full truncate text-xs font-bold leading-tight">
                          {champ_stat.champion.name}
                        </p>
                        <p class="text-[0.7rem] font-medium text-base-content/50">
                          {champ_stat.games_played} games
                        </p>
                        <span class={[
                          "rounded px-1.5 py-0.5 text-[0.7rem] font-bold border",
                          win_rate_bg(champ_stat.win_rate)
                        ]}>
                          {champ_stat.win_rate}%
                        </span>
                      </div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Empty state when no champion selected --%>
        <%= if is_nil(@selected_champion) && @top_champions != [] do %>
          <div class="py-10 text-center text-base-content/40">
            <.icon name="hero-cursor-arrow-rays" class="mx-auto h-8 w-8 mb-2" />
            <p class="text-sm">Select a champion above to view detailed stats.</p>
          </div>
        <% end %>

        <%!-- Results --%>
        <%= if @result do %>
          <div id="receipts-result" class="space-y-5">
            <div class="flex flex-col gap-4 rounded-xl border border-base-300 bg-base-200 p-5 shadow-sm sm:flex-row sm:items-center">
              <img
                src={champion_icon_url(@result.champion)}
                alt={@result.champion.name}
                class="h-16 w-16 rounded-xl border-2 border-base-300 object-cover shadow-md"
                onerror="this.style.display='none'"
              />
              <div class="min-w-0 flex-1">
                <p class="text-xs font-medium uppercase tracking-wide text-base-content/40">
                  {@player.name} on
                </p>
                <h2 class="text-3xl font-bold tracking-tight">{@result.champion.name}</h2>
                <%= if @result.games_played == 0 do %>
                  <p class="mt-1 text-sm text-base-content/50">
                    No games on record for the selected filters.
                  </p>
                <% end %>
              </div>
            </div>

            <%= if @result.games_played > 0 do %>
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center shadow-sm">
                  <p class="text-3xl font-bold">{@result.games_played}</p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
                    Games
                  </p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center shadow-sm">
                  <p class={["text-3xl font-bold", win_rate_color(@result.win_rate)]}>
                    {@result.win_rate}%
                  </p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
                    Win Rate
                  </p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center shadow-sm">
                  <p class="text-3xl font-bold">
                    {@result.avg_kills}/{@result.avg_deaths}/{@result.avg_assists}
                  </p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
                    KDA · {@result.kda_ratio}:1
                  </p>
                </div>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 text-center shadow-sm">
                  <p class="text-3xl font-bold">{@result.avg_cs}</p>
                  <p class="mt-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
                    Avg CS
                  </p>
                </div>
              </div>

              <div class="space-y-2">
                <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Recent Games
                </h3>
                <div class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
                  <%= for game <- @result.recent_games do %>
                    <div class="flex items-center gap-3 border-b border-base-300 px-4 py-3 last:border-b-0">
                      <div class={[
                        "w-12 shrink-0 rounded text-center py-0.5 text-xs font-bold",
                        if(game.win,
                          do: "bg-success/20 text-success",
                          else: "bg-error/20 text-error"
                        )
                      ]}>
                        {if game.win, do: "WIN", else: "LOSS"}
                      </div>
                      <div class="min-w-0 flex-1">
                        <p class="text-sm font-semibold">
                          {game.kills}/{game.deaths}/{game.assists}
                          <span class="font-normal text-base-content/40">·</span>
                          {game.cs} CS
                          <%= if game.position && game.position != "" do %>
                            <span class="font-normal text-base-content/40">·</span>
                            {game.position}
                          <% end %>
                        </p>
                        <p class="text-xs text-base-content/40">
                          {Queue.label(game.match.queue_type)}
                        </p>
                      </div>
                      <div class="shrink-0 text-right">
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
