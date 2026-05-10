defmodule ReceiptsWeb.PlayerSelectLive do
  use ReceiptsWeb, :live_view

  alias Receipts.LoL.Player
  alias Receipts.LoL.Queries

  @impl true
  def mount(_params, _session, socket) do
    players = Ash.read!(Player)
    player_top_champions = Queries.player_top_champions(players)

    {:ok,
     socket
     |> assign(:players, players)
     |> assign(:player_top_champions, player_top_champions)}
  end

  defp champion_icon_url(champion) do
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/#{champion.riot_id}.png"
  end

  defp win_rate_color(rate) when rate >= 55.0, do: "text-success"
  defp win_rate_color(rate) when rate < 45.0, do: "text-error"
  defp win_rate_color(_), do: "text-base-content"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for player <- @players do %>
              <% top_champ = Map.get(@player_top_champions, player.id) %>
              <.link navigate={~p"/players/#{player.id}"} id={"player-tile-#{player.id}"}>
                <div class="group relative overflow-hidden rounded-2xl border border-base-300 bg-base-200 p-5 shadow-sm transition-all duration-200 hover:border-primary/50 hover:shadow-md hover:-translate-y-0.5 cursor-pointer h-full">
                  <%!-- Blurred champion art background --%>
                  <%= if top_champ do %>
                    <div class="pointer-events-none absolute inset-0 opacity-[0.05] group-hover:opacity-[0.09] transition-opacity duration-300">
                      <img
                        src={champion_icon_url(top_champ.champion)}
                        alt=""
                        class="h-full w-full object-cover scale-150 blur-2xl"
                      />
                    </div>
                  <% end %>

                  <div class="relative flex items-center gap-4">
                    <%= if top_champ do %>
                      <img
                        src={champion_icon_url(top_champ.champion)}
                        alt={top_champ.champion.name}
                        class="h-16 w-16 shrink-0 rounded-xl border-2 border-base-300 object-cover shadow-md"
                        onerror="this.style.display='none'"
                      />
                    <% else %>
                      <div class="flex h-16 w-16 shrink-0 items-center justify-center rounded-xl border-2 border-base-300 bg-base-300 text-base-content/30">
                        <.icon name="hero-question-mark-circle" class="h-8 w-8" />
                      </div>
                    <% end %>

                    <div class="min-w-0 flex-1">
                      <h2 class="text-xl font-bold tracking-tight truncate">{player.name}</h2>
                      <%= if top_champ do %>
                        <p class="text-sm text-base-content/55 truncate mt-0.5">
                          Most played:
                          <span class="font-semibold text-base-content/80">
                            {top_champ.champion.name}
                          </span>
                        </p>
                        <div class="mt-1.5 flex items-center gap-3">
                          <span class="text-xs text-base-content/45">
                            {top_champ.games_played} games
                          </span>
                          <span class={["text-xs font-bold", win_rate_color(top_champ.win_rate)]}>
                            {top_champ.win_rate}% WR
                          </span>
                        </div>
                      <% else %>
                        <p class="text-sm text-base-content/40 mt-0.5">No games synced yet</p>
                      <% end %>
                    </div>

                    <.icon
                      name="hero-chevron-right"
                      class="h-5 w-5 shrink-0 text-base-content/25 group-hover:text-primary transition-colors"
                    />
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
