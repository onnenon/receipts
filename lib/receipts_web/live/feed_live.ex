defmodule ReceiptsWeb.FeedLive do
  use ReceiptsWeb, :live_view

  alias Receipts.LoL.{Queue, Queries}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :recent_games, Queries.recent_games(limit: 20))}
  end

  defp champion_icon_url(champion) do
    "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/champion-icons/#{champion.riot_id}.png"
  end

  defp result_card_classes(true), do: "border-success/35 bg-success/5 hover:border-success/50"
  defp result_card_classes(false), do: "border-error/35 bg-error/5 hover:border-error/50"
  defp result_card_classes(_), do: "border-base-300/70 bg-base-200 hover:border-primary/30"

  defp result_header_classes(true), do: "border-success/20 bg-success/10"
  defp result_header_classes(false), do: "border-error/20 bg-error/10"
  defp result_header_classes(_), do: "border-base-300/60 bg-base-200"

  defp game_result(participants) do
    participants
    |> Enum.map(& &1.win)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [result] -> result
      _ -> nil
    end
  end

  defp result_label(true), do: "Win"
  defp result_label(false), do: "Loss"
  defp result_label(_), do: "Unknown"

  defp format_duration(nil), do: "-"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y at %-I:%M %p UTC")
  end

  defp format_number(nil), do: "-"

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp cs_per_min(_cs, nil), do: "-"
  defp cs_per_min(nil, _duration), do: "-"
  defp cs_per_min(_cs, duration) when duration <= 0, do: "-"

  defp cs_per_min(cs, duration) do
    Float.round(cs / (duration / 60), 1)
  end

  defp kda_ratio(kills, deaths, assists) do
    ((kills || 0) + (assists || 0)) / max(deaths || 0, 1)
  end

  defp format_kda_ratio(kills, deaths, assists) do
    :erlang.float_to_binary(kda_ratio(kills, deaths, assists), decimals: 2)
  end

  defp stat_color(nil, _stat), do: "text-base-content/60"
  defp stat_color(value, :kda) when value >= 4.0, do: "text-success"
  defp stat_color(value, :kda) when value < 2.0, do: "text-error"
  defp stat_color(_value, :kda), do: "text-base-content/90"
  defp stat_color(value, :cs_per_min) when is_number(value) and value >= 7.0, do: "text-success"
  defp stat_color(value, :cs_per_min) when is_number(value) and value < 5.0, do: "text-error"
  defp stat_color(_value, :cs_per_min), do: "text-base-content/90"
  defp stat_color(value, :damage) when value >= 20_000, do: "text-success"
  defp stat_color(value, :damage) when value < 8_000, do: "text-error"
  defp stat_color(_value, :damage), do: "text-base-content/90"

  defp stat_color(value, :vision_per_min) when is_number(value) and value >= 1.0,
    do: "text-success"

  defp stat_color(value, :vision_per_min) when is_number(value) and value < 0.35, do: "text-error"
  defp stat_color(_value, :vision_per_min), do: "text-base-content/90"

  defp per_minute(_value, nil), do: nil
  defp per_minute(nil, _duration), do: nil
  defp per_minute(_value, duration) when duration <= 0, do: nil

  defp per_minute(value, duration) do
    Float.round(value / (duration / 60), 1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} admin_authenticated={@admin_authenticated}>
      <section id="recent-games-feed" class="space-y-5">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-widest text-primary">Ranked feed</p>
            <h1 class="text-3xl font-bold tracking-tight">Feed</h1>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/55">
              The most recent ranked solo/duo and ranked flex games across all registered players.
            </p>
          </div>
          <p class="text-sm text-base-content/50">
            Last {length(@recent_games)} ranked games
          </p>
        </div>

        <%= if @recent_games == [] do %>
          <div
            id="recent-games-empty"
            class="rounded-xl border border-dashed border-base-300 bg-base-200/50 px-5 py-12 text-center text-sm text-base-content/45"
          >
            No ranked solo/duo or ranked flex games synced yet.
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for game <- @recent_games do %>
              <article
                id={"recent-game-#{game.id}"}
                class={[
                  "overflow-hidden rounded-xl border shadow-sm transition hover:shadow-md",
                  result_card_classes(game_result(game.participants))
                ]}
              >
                <div
                  id={"recent-game-#{game.id}-summary"}
                  class={[
                    "flex flex-col gap-3 border-b px-4 py-3 sm:flex-row sm:items-center sm:justify-between",
                    result_header_classes(game_result(game.participants))
                  ]}
                >
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <h2 class="text-sm font-bold text-base-content/90">
                        {Queue.label(game.match.queue_type)}
                      </h2>
                      <%= if game.known_player_count > 1 do %>
                        <span class="inline-flex items-center gap-1 rounded-full border border-sky-400/25 bg-sky-400/10 px-2 py-0.5 text-xs font-bold text-sky-300">
                          <.icon name="hero-user-group" class="h-3.5 w-3.5" />
                          {game.known_player_count} players together
                        </span>
                      <% end %>
                    </div>
                    <p class="mt-1 text-xs text-base-content/45">
                      {format_datetime(game.match.game_datetime)}
                    </p>
                  </div>

                  <div class="text-right">
                    <div class="rounded-lg bg-base-300/40 px-3 py-2">
                      <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/40">
                        Duration
                      </p>
                      <p class="text-sm font-bold tabular-nums">
                        {format_duration(game.match.game_duration_seconds)}
                      </p>
                    </div>
                  </div>
                </div>

                <div class="divide-y divide-base-300/50">
                  <%= for participant <- game.participants do %>
                    <div
                      id={"recent-game-#{game.id}-player-#{participant.player.id}"}
                      aria-label={"#{participant.player.name} #{result_label(participant.win)}"}
                      class="grid gap-3 px-4 py-3 transition sm:grid-cols-[minmax(0,1.4fr)_auto] sm:items-center"
                    >
                      <div class="flex min-w-0 items-center gap-3">
                        <img
                          src={champion_icon_url(participant.champion)}
                          alt={participant.champion.name}
                          class="h-11 w-11 shrink-0 rounded-lg border border-base-300 object-cover"
                          onerror="this.style.display='none'"
                        />
                        <div class="min-w-0">
                          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                            <p class="truncate text-sm font-extrabold">
                              {participant.player.name}
                            </p>
                          </div>
                          <p class="truncate text-xs text-base-content/50">
                            {participant.champion.name}
                            <%= if participant.position do %>
                              · {String.capitalize(String.downcase(participant.position))}
                            <% end %>
                          </p>
                        </div>
                      </div>

                      <div class="grid grid-cols-4 gap-2 text-center sm:min-w-[27rem]">
                        <div>
                          <p
                            class={[
                              "text-sm font-bold tabular-nums",
                              stat_color(
                                kda_ratio(participant.kills, participant.deaths, participant.assists),
                                :kda
                              )
                            ]}
                          >
                            {participant.kills}/{participant.deaths}/{participant.assists}
                          </p>
                          <p
                            class={[
                              "text-[10px] font-semibold uppercase tracking-wide",
                              stat_color(
                                kda_ratio(participant.kills, participant.deaths, participant.assists),
                                :kda
                              )
                            ]}
                          >
                            {format_kda_ratio(participant.kills, participant.deaths, participant.assists)}
                            KDA
                          </p>
                        </div>
                        <div>
                          <p
                            class={[
                              "text-sm font-bold tabular-nums",
                              stat_color(
                                per_minute(participant.cs, game.match.game_duration_seconds),
                                :cs_per_min
                              )
                            ]}
                          >
                            {participant.cs}
                          </p>
                          <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/35">
                            CS ({cs_per_min(participant.cs, game.match.game_duration_seconds)}/m)
                          </p>
                        </div>
                        <div>
                          <p
                            class={[
                              "text-sm font-bold tabular-nums",
                              stat_color(participant.damage_dealt, :damage)
                            ]}
                          >
                            {format_number(participant.damage_dealt)}
                          </p>
                          <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/35">
                            Damage
                          </p>
                        </div>
                        <div>
                          <p
                            class={[
                              "text-sm font-bold tabular-nums",
                              stat_color(
                                per_minute(participant.vision_score, game.match.game_duration_seconds),
                                :vision_per_min
                              )
                            ]}
                          >
                            {participant.vision_score}
                          </p>
                          <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/35">
                            Vision
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </article>
            <% end %>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
