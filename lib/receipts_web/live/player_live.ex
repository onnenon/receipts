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

        player_position_stats =
          Queries.position_breakdown_for_player(player.id,
            queue_types: MapSet.to_list(enabled_queues)
          )

        {:ok,
         socket
         |> assign(:player, player)
         |> assign(:all_champions, all_champions)
         |> assign(:top_champions, top_champions)
         |> assign(:player_position_stats, player_position_stats)
         |> assign(:enabled_queues, enabled_queues)
         |> assign(:enabled_positions, MapSet.new())
         |> assign(:from_year, nil)
         |> assign(:to_year, nil)
         |> assign(:selected_champion, nil)
         |> assign(:champion_filter, "")
         |> assign(:champion_sort, :games)
         |> assign(:champion_limit, 20)
         |> assign(:min_games, nil)
         |> assign(:filters_open, true)
         |> assign(:champions_open, true)
         |> assign(:result, nil)
         |> assign(:recent_queue_filter, nil)}
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
    socket = assign(socket, :champion_sort, sort)
    socket = if sort != :win_rate, do: assign(socket, :min_games, nil), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_min_games", %{"min_games" => val}, socket) do
    min_games =
      case Integer.parse(val) do
        {n, ""} when n > 0 -> n
        _ -> nil
      end

    {:noreply, assign(socket, :min_games, min_games)}
  end

  @impl true
  def handle_event("set_champion_limit", %{"n" => n}, socket) do
    limit = if n == "all", do: nil, else: String.to_integer(n)
    {:noreply, assign(socket, :champion_limit, limit)}
  end

  @impl true
  def handle_event("toggle_position", %{"position" => position}, socket) do
    enabled =
      if MapSet.member?(socket.assigns.enabled_positions, position),
        do: MapSet.delete(socket.assigns.enabled_positions, position),
        else: MapSet.put(socket.assigns.enabled_positions, position)

    {:noreply, socket |> assign(:enabled_positions, enabled) |> maybe_rerun()}
  end

  @impl true
  def handle_event("clear_positions", _, socket) do
    {:noreply, socket |> assign(:enabled_positions, MapSet.new()) |> maybe_rerun()}
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
  def handle_event("set_recent_queue_filter", %{"queue" => queue}, socket) do
    filter = if queue == "", do: nil, else: queue
    {:noreply, assign(socket, :recent_queue_filter, filter)}
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
    %{
      player: player,
      enabled_queues: eq,
      enabled_positions: ep,
      from_year: from_year,
      to_year: to_year
    } = socket.assigns

    positions = MapSet.to_list(ep)
    queue_types = MapSet.to_list(eq)

    top_champions =
      Queries.top_champions_for_player(player.id,
        queue_types: queue_types,
        positions: positions,
        from_year: from_year,
        to_year: to_year
      )

    player_position_stats =
      Queries.position_breakdown_for_player(player.id,
        queue_types: queue_types,
        from_year: from_year,
        to_year: to_year
      )

    socket
    |> assign(:top_champions, top_champions)
    |> assign(:player_position_stats, player_position_stats)
  end

  defp run_query(socket) do
    %{
      player: player,
      selected_champion: champion,
      enabled_queues: eq,
      enabled_positions: ep,
      from_year: from_year,
      to_year: to_year
    } = socket.assigns

    opts = [
      queue_types: MapSet.to_list(eq),
      positions: MapSet.to_list(ep),
      from_year: from_year,
      to_year: to_year
    ]

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

  defp rank_icon_url(%{rank_tier: "EMERALD"}) do
    "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/ranked-mini-crests/emerald.svg"
  end

  defp rank_icon_url(%{rank_tier: tier}) when not is_nil(tier) do
    "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/ranked-mini-crests/#{String.downcase(tier)}.png"
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

  defp apply_sort_and_limit(top_champions, sort_by, limit, min_games) do
    filtered =
      case {sort_by, min_games} do
        {:win_rate, n} when is_integer(n) ->
          Enum.filter(top_champions, &(&1.games_played >= n))

        _ ->
          top_champions
      end

    sorted =
      case sort_by do
        :win_rate -> Enum.sort_by(filtered, &{-&1.win_rate, -&1.games_played})
        _ -> filtered
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

  defp champion_splash_url(champion) do
    "https://ddragon.leagueoflegends.com/cdn/img/champion/splash/#{champion.key}_0.jpg"
  end

  defp filter_recent_games(games, nil), do: games

  defp filter_recent_games(games, queue_filter) do
    Enum.filter(games, &(&1.match.queue_type == queue_filter))
  end

  @position_defs [
    {"TOP", "Top"},
    {"JUNGLE", "Jungle"},
    {"MIDDLE", "Mid"},
    {"BOTTOM", "Bot"},
    {"UTILITY", "Support"}
  ]

  defp position_defs, do: @position_defs

  defp position_label("TOP"), do: "Top"
  defp position_label("JUNGLE"), do: "Jungle"
  defp position_label("MIDDLE"), do: "Mid"
  defp position_label("BOTTOM"), do: "Bot"
  defp position_label("UTILITY"), do: "Support"
  defp position_label(p) when is_binary(p), do: String.capitalize(String.downcase(p))
  defp position_label(_), do: "Unknown"

  defp position_badge_class("TOP"), do: "bg-amber-500/20 text-amber-400 ring-amber-500/20"

  defp position_badge_class("JUNGLE"),
    do: "bg-emerald-500/20 text-emerald-400 ring-emerald-500/20"

  defp position_badge_class("MIDDLE"), do: "bg-sky-500/20 text-sky-400 ring-sky-500/20"
  defp position_badge_class("BOTTOM"), do: "bg-rose-500/20 text-rose-400 ring-rose-500/20"
  defp position_badge_class("UTILITY"), do: "bg-violet-500/20 text-violet-400 ring-violet-500/20"
  defp position_badge_class(_), do: "bg-base-300/50 text-base-content/50 ring-base-300/50"

  defp position_filter_active_class("TOP"), do: "bg-amber-500 text-white border-amber-500"
  defp position_filter_active_class("JUNGLE"), do: "bg-emerald-500 text-white border-emerald-500"
  defp position_filter_active_class("MIDDLE"), do: "bg-sky-500 text-white border-sky-500"
  defp position_filter_active_class("BOTTOM"), do: "bg-rose-500 text-white border-rose-500"
  defp position_filter_active_class("UTILITY"), do: "bg-violet-500 text-white border-violet-500"
  defp position_filter_active_class(_), do: "bg-primary text-primary-content border-primary"

  defp position_card_class("TOP"), do: "border-amber-500/30 bg-amber-500/10"
  defp position_card_class("JUNGLE"), do: "border-emerald-500/30 bg-emerald-500/10"
  defp position_card_class("MIDDLE"), do: "border-sky-500/30 bg-sky-500/10"
  defp position_card_class("BOTTOM"), do: "border-rose-500/30 bg-rose-500/10"
  defp position_card_class("UTILITY"), do: "border-violet-500/30 bg-violet-500/10"
  defp position_card_class(_), do: "border-base-300 bg-base-300/50"

  defp queue_button_class(queue_type, enabled_queues, positions_active?) do
    cond do
      positions_active? && !Queue.has_positions?(queue_type) ->
        "border-base-300/40 text-base-content/25 opacity-40 cursor-not-allowed"

      MapSet.member?(enabled_queues, queue_type) ->
        "bg-primary text-primary-content border-primary"

      true ->
        "border-base-300 text-base-content/50 hover:border-base-content/30 hover:text-base-content/70"
    end
  end

  defp win_rate_color(rate) when rate >= 55.0, do: "text-success"
  defp win_rate_color(rate) when rate < 45.0, do: "text-error"
  defp win_rate_color(_), do: "text-base-content"

  defp win_rate_bg(rate) when rate >= 55.0, do: "bg-success/15 text-success border-success/30"
  defp win_rate_bg(rate) when rate < 45.0, do: "bg-error/15 text-error border-error/30"
  defp win_rate_bg(_), do: "bg-base-300/50 text-base-content/70 border-base-300"

  defp rank_tier_glow(%{rank_tier: "CHALLENGER"}), do: "bg-yellow-300"
  defp rank_tier_glow(%{rank_tier: "GRANDMASTER"}), do: "bg-red-500"
  defp rank_tier_glow(%{rank_tier: "MASTER"}), do: "bg-purple-500"
  defp rank_tier_glow(%{rank_tier: "DIAMOND"}), do: "bg-blue-400"
  defp rank_tier_glow(%{rank_tier: "EMERALD"}), do: "bg-emerald-400"
  defp rank_tier_glow(%{rank_tier: "PLATINUM"}), do: "bg-cyan-400"
  defp rank_tier_glow(%{rank_tier: "GOLD"}), do: "bg-yellow-500"
  defp rank_tier_glow(%{rank_tier: "SILVER"}), do: "bg-slate-400"
  defp rank_tier_glow(%{rank_tier: "BRONZE"}), do: "bg-amber-700"
  defp rank_tier_glow(_), do: "bg-zinc-500"

  defp rank_tier_badge(%{rank_tier: "CHALLENGER"}),
    do: "border-yellow-400/30 bg-yellow-400/10 text-yellow-300"

  defp rank_tier_badge(%{rank_tier: "GRANDMASTER"}),
    do: "border-red-400/30 bg-red-400/10 text-red-300"

  defp rank_tier_badge(%{rank_tier: "MASTER"}),
    do: "border-purple-400/30 bg-purple-400/10 text-purple-300"

  defp rank_tier_badge(%{rank_tier: "DIAMOND"}),
    do: "border-blue-400/30 bg-blue-400/10 text-blue-300"

  defp rank_tier_badge(%{rank_tier: "EMERALD"}),
    do: "border-emerald-500/30 bg-emerald-500/10 text-emerald-300"

  defp rank_tier_badge(%{rank_tier: "PLATINUM"}),
    do: "border-cyan-500/30 bg-cyan-500/10 text-cyan-300"

  defp rank_tier_badge(%{rank_tier: "GOLD"}),
    do: "border-yellow-500/30 bg-yellow-500/10 text-yellow-200"

  defp rank_tier_badge(%{rank_tier: "SILVER"}),
    do: "border-slate-400/30 bg-slate-400/10 text-slate-300"

  defp rank_tier_badge(%{rank_tier: "BRONZE"}),
    do: "border-amber-700/30 bg-amber-700/10 text-amber-500"

  defp rank_tier_badge(%{rank_tier: "IRON"}),
    do: "border-zinc-500/30 bg-zinc-500/10 text-zinc-400"

  defp rank_tier_badge(_), do: "border-base-300 bg-base-300/50 text-base-content/70"

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
      |> assign(:position_defs, position_defs())
      |> assign(:positions_active?, MapSet.size(assigns.enabled_positions) > 0)
      |> assign(:total_games, total_games(assigns.top_champions))
      |> assign(:overall_wr, overall_win_rate(assigns.top_champions))
      |> assign(
        :displayed_champions,
        assigns.top_champions
        |> filter_champions_by_name(assigns.champion_filter)
        |> apply_sort_and_limit(assigns.champion_sort, assigns.champion_limit, assigns.min_games)
      )

    ~H"""
    <Layouts.app flash={@flash} admin_authenticated={@admin_authenticated}>
      <div class="space-y-6">
        <%!-- Header --%>
        <% best = best_rank(@player.accounts) %>
        <div class="relative overflow-hidden rounded-2xl border border-base-300 bg-base-200">
          <%!-- Rank tier glow --%>
          <%= if best do %>
            <div class={[
              "pointer-events-none absolute -right-12 -top-12 h-64 w-64 rounded-full blur-3xl opacity-15",
              rank_tier_glow(best)
            ]}>
            </div>
          <% end %>
          <div class="relative flex items-start gap-4 p-5">
            <%!-- Back button --%>
            <.link
              navigate={~p"/"}
              class="mt-1 rounded-lg p-1.5 text-base-content/50 transition hover:bg-base-300 hover:text-base-content"
            >
              <.icon name="hero-arrow-left" class="h-5 w-5" />
            </.link>
            <%!-- Player info --%>
            <div class="min-w-0 flex-1">
              <p class="text-xs font-semibold uppercase tracking-widest text-primary">Receipts</p>
              <div class="mt-0.5 flex flex-wrap items-center gap-3">
                <h1 class="text-3xl font-bold tracking-tight">{@player.name}</h1>
                <%= if best do %>
                  <div class={[
                    "flex items-center gap-2 rounded-xl border px-3 py-1.5",
                    rank_tier_badge(best)
                  ]}>
                    <img
                      src={rank_icon_url(best)}
                      alt={rank_label(best)}
                      class="h-8 w-8 object-contain"
                      onerror="this.style.display='none'"
                    />
                    <span class="text-sm font-bold">{rank_label(best)}</span>
                    <span class="text-xs opacity-60">{best.rank_lp} LP</span>
                  </div>
                <% end %>
              </div>
              <div class="mt-3 flex flex-wrap items-center gap-2">
                <%= if @total_games > 0 do %>
                  <span class="inline-flex items-center rounded-lg border border-base-300 bg-base-300/40 px-2.5 py-1 text-xs font-medium text-base-content/60">
                    {@total_games} games tracked
                  </span>
                  <span class={[
                    "inline-flex items-center rounded-lg border px-2.5 py-1 text-xs font-bold",
                    win_rate_bg(@overall_wr)
                  ]}>
                    {@overall_wr}% WR
                  </span>
                  <%= if @player.oldest_game_date do %>
                    <span class="inline-flex items-center rounded-lg border border-base-300 bg-base-300/30 px-2.5 py-1 text-xs text-base-content/45">
                      since {Calendar.strftime(@player.oldest_game_date, "%b %Y")}
                    </span>
                  <% end %>
                <% end %>
                <%= for account <- @player.accounts do %>
                  <a
                    href={opgg_url(account)}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-1 rounded-lg border border-base-300 bg-base-200 px-2.5 py-1 text-xs font-medium text-base-content/55 transition hover:border-primary/40 hover:text-primary"
                  >
                    {account.riot_game_name}#{account.riot_tag_line}
                    <.icon name="hero-arrow-top-right-on-square-mini" class="h-3 w-3" />
                  </a>
                <% end %>
              </div>
              <%!-- Player position breakdown --%>
              <%= if @player_position_stats != [] do %>
                <div class="mt-3 flex flex-wrap gap-2">
                  <%= for ps <- @player_position_stats do %>
                    <div class={[
                      "flex items-center gap-2 rounded-lg border px-3 py-1.5",
                      position_card_class(ps.position)
                    ]}>
                      <span class="text-xs font-bold text-base-content/80">
                        {position_label(ps.position)}
                      </span>
                      <span class="text-xs text-base-content/50">{ps.games} games</span>
                      <span class={["text-xs font-semibold", win_rate_color(ps.win_rate)]}>
                        {ps.win_rate}%
                      </span>
                    </div>
                  <% end %>
                </div>
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
                <%= if @positions_active? do %>
                  · {MapSet.size(@enabled_positions)} position{if MapSet.size(@enabled_positions) == 1, do: "", else: "s"}
                <% end %>
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
                      disabled={@positions_active? && !Queue.has_positions?(queue_type)}
                      class={[
                        "rounded-lg px-3 py-2 text-left text-xs font-semibold border transition-colors",
                        queue_button_class(queue_type, @enabled_queues, @positions_active?)
                      ]}
                    >
                      {label}
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Position filter --%>
              <div>
                <div class="mb-2 flex items-center justify-between">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    Position
                  </p>
                  <%= if @positions_active? do %>
                    <button
                      id="clear-positions"
                      type="button"
                      phx-click="clear_positions"
                      class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold transition hover:bg-base-300"
                    >
                      All positions
                    </button>
                  <% end %>
                </div>
                <div class="flex flex-wrap gap-2">
                  <%= for {pos, label} <- @position_defs do %>
                    <button
                      id={"position-toggle-#{pos}"}
                      phx-click="toggle_position"
                      phx-value-position={pos}
                      class={[
                        "rounded-lg px-4 py-2 text-xs font-bold border transition-colors",
                        if(MapSet.member?(@enabled_positions, pos),
                          do: position_filter_active_class(pos),
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
                    <%= if @champion_sort == :win_rate do %>
                      <form id="min-games-form" phx-change="set_min_games" class="flex items-center gap-1.5 ml-1">
                        <span class="text-xs text-base-content/40">min</span>
                        <input
                          type="number"
                          name="min_games"
                          id="min-games-input"
                          value={@min_games}
                          min="1"
                          placeholder="games"
                          class="w-20 rounded-md border border-base-300 bg-base-100 px-2 py-1 text-xs text-base-content/80 placeholder-base-content/30 focus:border-primary focus:outline-none"
                        />
                      </form>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-xs text-base-content/40 mr-1">Show</span>
                    <%= for {label, n} <- [{"10", 10}, {"20", 20}, {"All", nil}] do %>
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
            <%!-- Title card — cinematic champion banner --%>
            <div class="relative overflow-hidden rounded-2xl border border-white/10 shadow-2xl" style="min-height: 160px;">
              <%!-- Splash art: img tag so it loads reliably, filter via inline style --%>
              <img
                src={champion_splash_url(@result.champion)}
                alt=""
                class="absolute inset-0 h-full w-full object-cover object-right scale-110 pointer-events-none select-none"
                style="filter: blur(0px) brightness(0.45);"
                onerror="this.style.display='none'"
              />
              <%!-- Strong gradient from left keeps text legible while revealing art on right --%>
              <div class="absolute inset-0 bg-gradient-to-r from-black/95 via-black/65 to-transparent"></div>
              <%!-- Subtle bottom vignette --%>
              <div class="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/50 to-transparent"></div>
              <%!-- Content --%>
              <div class="relative flex items-center gap-5 px-7 py-8">
                <div class="relative shrink-0">
                  <img
                    src={champion_icon_url(@result.champion)}
                    alt={@result.champion.name}
                    class="h-20 w-20 rounded-2xl object-cover shadow-2xl ring-2 ring-white/20"
                    onerror="this.style.display='none'"
                  />
                </div>
                <div class="min-w-0">
                  <p class="mb-1 text-xs font-semibold uppercase tracking-[0.18em] text-white/40">
                    {@player.name} on
                  </p>
                  <h2 class="text-5xl font-black leading-none tracking-tight text-white drop-shadow-lg">
                    {@result.champion.name}
                  </h2>
                  <%= if @result.games_played == 0 do %>
                    <p class="mt-2 text-sm text-white/40">
                      No games on record for the selected filters.
                    </p>
                  <% end %>
                </div>
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

              <%!-- Per-champion position breakdown --%>
              <%= if @result.position_stats != [] do %>
                <div class="rounded-xl border border-base-300 bg-base-200 p-4 shadow-sm">
                  <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-base-content/50">
                    Win Rate by Position
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <%= for ps <- @result.position_stats do %>
                      <div class={[
                        "flex items-center gap-2.5 rounded-xl border px-4 py-2.5",
                        position_card_class(ps.position)
                      ]}>
                        <span class="text-sm font-bold">{position_label(ps.position)}</span>
                        <span class="text-xs text-base-content/50">{ps.games} games</span>
                        <span class={["text-sm font-bold", win_rate_color(ps.win_rate)]}>
                          {ps.win_rate}%
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <div class="space-y-2">
                <% unique_queues = @result.recent_games |> Enum.map(& &1.match.queue_type) |> Enum.uniq() %>
                <% filtered_games = filter_recent_games(@result.recent_games, @recent_queue_filter) %>
                <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                  <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                    Recent Games
                    <span class="ml-1 font-normal normal-case text-base-content/40">
                      ({length(filtered_games)} of {length(@result.recent_games)})
                    </span>
                  </h3>
                  <%= if length(unique_queues) > 1 do %>
                    <div class="flex flex-wrap gap-1">
                      <button
                        phx-click="set_recent_queue_filter"
                        phx-value-queue=""
                        class={[
                          "rounded-full px-3 py-0.5 text-xs font-medium transition-colors",
                          if(is_nil(@recent_queue_filter),
                            do: "bg-primary/80 text-primary-content",
                            else: "bg-base-300 text-base-content/60 hover:bg-base-300/70"
                          )
                        ]}
                      >All</button>
                      <%= for queue_type <- unique_queues do %>
                        <button
                          phx-click="set_recent_queue_filter"
                          phx-value-queue={queue_type}
                          class={[
                            "rounded-full px-3 py-0.5 text-xs font-medium transition-colors",
                            if(@recent_queue_filter == queue_type,
                              do: "bg-primary/80 text-primary-content",
                              else: "bg-base-300 text-base-content/60 hover:bg-base-300/70"
                            )
                          ]}
                        >{Queue.label(queue_type)}</button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
                  <%= if filtered_games == [] do %>
                    <div class="py-8 text-center text-sm text-base-content/40">
                      No games match the selected filters.
                    </div>
                  <% end %>
                  <%= for game <- filtered_games do %>
                    <div class="flex items-center gap-3 border-b border-base-300 px-4 py-3 last:border-b-0 hover:bg-base-300/30 transition-colors">
                      <%!-- Win/Loss indicator bar on left edge --%>
                      <div class={[
                        "w-1 self-stretch rounded-full shrink-0",
                        if(game.win, do: "bg-success", else: "bg-error")
                      ]} />
                      <%!-- WIN/LOSS badge --%>
                      <div class={[
                        "w-11 shrink-0 rounded-md py-1 text-center text-xs font-bold tracking-wide",
                        if(game.win,
                          do: "bg-success/15 text-success",
                          else: "bg-error/15 text-error"
                        )
                      ]}>
                        {if game.win, do: "WIN", else: "LOSS"}
                      </div>
                      <div class="min-w-0 flex-1">
                        <div class="flex items-center gap-2 flex-wrap">
                          <p class="text-sm font-semibold">
                            {game.kills}/{game.deaths}/{game.assists}
                            <span class="font-normal text-base-content/40 mx-0.5">·</span>
                            {game.cs} CS
                          </p>
                          <%= if game.position && game.position != "" do %>
                            <span class={[
                              "inline-flex items-center rounded px-1.5 py-px text-xs font-bold uppercase tracking-wide ring-1",
                              position_badge_class(game.position)
                            ]}>
                              {position_label(game.position)}
                            </span>
                          <% end %>
                        </div>
                        <p class="text-xs text-base-content/40 mt-0.5">
                          {Queue.label(game.match.queue_type)}
                        </p>
                      </div>
                      <div class="shrink-0 text-right">
                        <p class="text-xs font-medium text-base-content/50">
                          {format_duration(game.match.game_duration_seconds)}
                        </p>
                        <p class="text-xs text-base-content/35 mt-0.5">
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
