defmodule ReceiptsWeb.PlayerSelectLive do
  use ReceiptsWeb, :live_view

  alias Receipts.LoL.Player
  alias Receipts.LoL.Queries

  @impl true
  def mount(_params, _session, socket) do
    players = Ash.read!(Player)
    home_stats = Queries.player_home_stats(players)

    {:ok,
     socket
     |> assign(:players, players)
     |> assign(:home_stats, home_stats)}
  end

  defp champion_icon_url(champion) do
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/#{champion.riot_id}.png"
  end

  defp champion_splash_url(champion) do
    "https://ddragon.leagueoflegends.com/cdn/img/champion/splash/#{champion.key}_0.jpg"
  end

  defp win_rate_color(rate) when rate >= 55.0, do: "text-emerald-400"
  defp win_rate_color(rate) when rate < 45.0, do: "text-red-400"
  defp win_rate_color(_), do: "text-base-content/70"

  defp tier_classes("IRON"), do: {"text-slate-400", "bg-slate-700/50 border-slate-600/40"}
  defp tier_classes("BRONZE"), do: {"text-amber-600", "bg-amber-950/60 border-amber-700/40"}
  defp tier_classes("SILVER"), do: {"text-slate-300", "bg-slate-600/50 border-slate-500/40"}
  defp tier_classes("GOLD"), do: {"text-yellow-400", "bg-yellow-950/60 border-yellow-700/40"}
  defp tier_classes("PLATINUM"), do: {"text-cyan-400", "bg-cyan-950/60 border-cyan-700/40"}

  defp tier_classes("EMERALD"),
    do: {"text-emerald-400", "bg-emerald-950/60 border-emerald-700/40"}

  defp tier_classes("DIAMOND"), do: {"text-blue-400", "bg-blue-950/60 border-blue-700/40"}
  defp tier_classes("MASTER"), do: {"text-purple-400", "bg-purple-950/60 border-purple-700/40"}
  defp tier_classes("GRANDMASTER"), do: {"text-red-400", "bg-red-950/60 border-red-700/40"}

  defp tier_classes("CHALLENGER"),
    do: {"text-yellow-300", "bg-yellow-900/60 border-yellow-600/40"}

  defp tier_classes(_), do: {"text-base-content/50", "bg-base-300/50 border-base-300/40"}

  defp format_rank(%{tier: tier, division: div, lp: lp}) do
    no_division = tier in ~w(MASTER GRANDMASTER CHALLENGER)

    tier_label =
      tier
      |> String.downcase()
      |> String.capitalize()

    if no_division do
      "#{tier_label} #{lp}LP"
    else
      "#{tier_label} #{div}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} admin_authenticated={@admin_authenticated}>
      <div class="space-y-8">
        <div class="text-center space-y-2 pt-4">
          <p class="text-xs font-semibold uppercase tracking-widest text-primary">Who's up?</p>
          <h1 class="text-4xl font-bold tracking-tight">Select a Player</h1>
          <p class="text-sm text-base-content/55 max-w-lg mx-auto leading-6">
            Pull up the receipts — see what they've actually been playing and how it's going.
          </p>
        </div>

        <%= if @players == [] do %>
          <div class="py-20 text-center text-base-content/40">
            <.icon name="hero-user-group" class="mx-auto h-12 w-12 mb-3" />
            <p class="text-sm">No players registered yet.</p>
            <.link
              navigate={~p"/admin/players"}
              class="mt-2 inline-block text-sm text-primary hover:underline"
            >
              Add players in Admin
            </.link>
          </div>
        <% else %>
          <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <%= for player <- @players do %>
              <% stats = Map.get(@home_stats, player.id, %{}) %>
              <% top_champ = Map.get(stats, :top_champion) %>
              <% total_games = Map.get(stats, :total_games, 0) %>
              <% overall_win_rate = Map.get(stats, :overall_win_rate, 0.0) %>
              <% best_rank = Map.get(stats, :best_rank) %>
              <.link navigate={~p"/players/#{player.id}"} id={"player-tile-#{player.id}"}>
                <div class="group relative overflow-hidden rounded-2xl border border-base-300/60 bg-base-200 shadow-md transition-all duration-200 hover:border-primary/40 hover:shadow-xl hover:-translate-y-1 cursor-pointer flex flex-col">
                  <%!-- Hero: blurred splash bg + icon + player name + rank --%>
                  <div class="relative overflow-hidden bg-base-300 shrink-0">
                    <%= if top_champ do %>
                      <img
                        src={champion_splash_url(top_champ.champion)}
                        alt=""
                        class="absolute inset-0 h-full w-full object-cover object-top scale-110 blur-sm opacity-60 group-hover:opacity-70 transition-opacity duration-300"
                        onerror="this.style.display='none'"
                      />
                    <% end %>
                    <div class="absolute inset-0 bg-black/55" />

                    <div class="relative p-5">
                      <div class="flex items-start justify-between gap-4">
                        <%!-- Left: all text info --%>
                        <div class="min-w-0 flex-1">
                          <h2 class="text-2xl font-extrabold tracking-tight text-white drop-shadow truncate">
                            {player.name}
                          </h2>
                          <%= if best_rank do %>
                            <% {text_cls, bg_cls} = tier_classes(best_rank.tier) %>
                            <span class={[
                              "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold border mt-1",
                              text_cls,
                              bg_cls
                            ]}>
                              {format_rank(best_rank)}
                            </span>
                          <% else %>
                            <span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium border mt-1 text-white/35 bg-white/5 border-white/10">
                              Unranked
                            </span>
                          <% end %>
                          <%= if top_champ do %>
                            <p class="text-[10px] text-white/50 font-semibold uppercase tracking-widest mt-3">
                              Most Played
                            </p>
                            <p class="text-sm font-bold text-white/85 truncate">
                              {top_champ.champion.name}
                            </p>
                            <div class="flex items-center gap-2 mt-0.5">
                              <span class="text-xs text-white/45">
                                {top_champ.games_played} games
                              </span>
                              <span class="text-white/25">·</span>
                              <span class={["text-xs font-semibold", win_rate_color(top_champ.win_rate)]}>
                                {top_champ.win_rate}% WR
                              </span>
                            </div>
                          <% else %>
                            <p class="text-sm text-white/30 mt-2">No games synced</p>
                          <% end %>
                        </div>

                        <%!-- Right: champion icon --%>
                        <%= if top_champ do %>
                          <img
                            src={champion_icon_url(top_champ.champion)}
                            alt={top_champ.champion.name}
                            class="h-20 w-20 shrink-0 rounded-2xl border-2 border-white/20 object-cover shadow-xl"
                            onerror="this.style.display='none'"
                          />
                        <% else %>
                          <div class="flex h-20 w-20 shrink-0 items-center justify-center rounded-2xl border-2 border-white/10 bg-white/5 text-white/30">
                            <.icon name="hero-question-mark-circle" class="h-9 w-9" />
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <%!-- Stats bar --%>
                  <div class="grid grid-cols-2 divide-x divide-base-300/50 border-t border-base-300/50">
                    <div class="px-4 py-3 text-center">
                      <p class="text-xl font-bold tabular-nums text-base-content/90">
                        {total_games}
                      </p>
                      <p class="text-[10px] text-base-content/40 uppercase tracking-wide font-medium mt-0.5">
                        Games
                      </p>
                    </div>
                    <div class="px-4 py-3 text-center">
                      <p class={["text-xl font-bold tabular-nums", win_rate_color(overall_win_rate)]}>
                        {overall_win_rate}%
                      </p>
                      <p class="text-[10px] text-base-content/40 uppercase tracking-wide font-medium mt-0.5">
                        Win Rate
                      </p>
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
