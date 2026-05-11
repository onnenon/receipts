defmodule ReceiptsWeb.AIComponents do
  use Phoenix.Component

  attr(:suggestion, :map, required: true)
  attr(:generated_at, :any, default: nil)

  def comp_suggestion_result(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p class="max-w-3xl text-sm leading-6 text-base-content/70">
            {@suggestion["summary"]}
          </p>
          <p :if={@generated_at} class="mt-1 text-xs text-base-content/40">
            Generated {format_datetime(@generated_at)}
          </p>
        </div>
        <span class={[
          "inline-flex shrink-0 items-center rounded-lg border px-2.5 py-1 text-xs font-bold capitalize",
          confidence_badge_class(@suggestion["confidence"])
        ]}>
          {@suggestion["confidence"]} confidence
        </span>
      </div>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        <%= for slot <- @suggestion["recommended_lineup"] do %>
          <article
            id={"comp-slot-#{slot["player_id"]}"}
            class={["rounded-xl border p-4", position_card_class(slot["position"])]}
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <h3 class="text-lg font-bold tracking-tight">{slot["player_name"]}</h3>
                <p class="text-sm font-semibold text-base-content/60">{slot["position_label"]}</p>
              </div>
              <span class={[
                "inline-flex rounded-md px-2 py-1 text-xs font-bold ring-1",
                position_badge_class(slot["position"])
              ]}>
                {slot["position_label"]}
              </span>
            </div>

            <%= if slot["champions"] != [] do %>
              <div class="mt-3 flex flex-wrap gap-1.5">
                <%= for champion <- slot["champions"] do %>
                  <span class="rounded-md border border-base-300 bg-base-100/70 px-2 py-1 text-xs font-semibold text-base-content/70">
                    {champion}
                  </span>
                <% end %>
              </div>
            <% end %>

            <p class="mt-3 text-sm leading-6 text-base-content/70">{slot["reason"]}</p>

            <%= if slot["evidence"] != [] do %>
              <ul class="mt-3 space-y-1.5">
                <%= for evidence <- slot["evidence"] do %>
                  <li class="flex gap-2 text-xs leading-5 text-base-content/55">
                    <span class="mt-2 h-1 w-1 shrink-0 rounded-full bg-base-content/35"></span>
                    <span>{evidence}</span>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </article>
        <% end %>
      </div>

      <%= if @suggestion["alternatives"] != [] do %>
        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Alternatives
          </p>
          <div class="grid gap-3 md:grid-cols-2">
            <%= for alternative <- @suggestion["alternatives"] do %>
              <div class="space-y-3 rounded-xl border border-base-300 bg-base-100/60 p-3">
                <p class="text-sm font-bold">{alternative["name"]}</p>
                <p class="mt-1 text-xs leading-5 text-base-content/55">{alternative["notes"]}</p>
                <%= if alternative["lineup"] != [] do %>
                  <div class="grid gap-1.5">
                    <%= for slot <- alternative["lineup"] do %>
                      <div class="flex items-center justify-between gap-3 rounded-lg border border-base-300 bg-base-200/70 px-2.5 py-2">
                        <span class="truncate text-xs font-semibold text-base-content/75">
                          {slot["player_name"]}
                        </span>
                        <span class={[
                          "shrink-0 rounded px-1.5 py-px text-xs font-bold ring-1",
                          position_badge_class(slot["position"])
                        ]}>
                          {slot["position_label"]}
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="rounded-lg border border-warning/30 bg-warning/10 px-2.5 py-2 text-xs text-warning">
                    Gemini did not return a full lineup for this alternative.
                  </p>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @suggestion["caveats"] != [] do %>
        <div class="rounded-xl border border-base-300 bg-base-100/60 p-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">Caveats</p>
          <ul class="mt-2 space-y-1">
            <%= for caveat <- @suggestion["caveats"] do %>
              <li class="text-xs leading-5 text-base-content/55">{caveat}</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  attr(:analysis, :map, required: true)
  attr(:generated_at, :any, default: nil)

  def win_loss_analysis_result(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p class="max-w-3xl text-sm leading-6 text-base-content/70">
            {@analysis["summary"]}
          </p>
          <p :if={@generated_at} class="mt-1 text-xs text-base-content/40">
            Generated {format_datetime(@generated_at)}
          </p>
        </div>
        <span class={[
          "inline-flex shrink-0 items-center rounded-lg border px-2.5 py-1 text-xs font-bold capitalize",
          confidence_badge_class(@analysis["confidence"])
        ]}>
          {@analysis["confidence"]} confidence
        </span>
      </div>

      <%= if @analysis["loss_causes"] != [] do %>
        <div class="grid gap-3 md:grid-cols-2">
          <%= for cause <- @analysis["loss_causes"] do %>
            <article class="rounded-xl border border-base-300 bg-base-100/60 p-4">
              <div class="flex items-start justify-between gap-3">
                <h3 class="text-sm font-bold">{cause["title"]}</h3>
                <span class={[
                  "rounded-md border px-2 py-0.5 text-xs font-bold capitalize",
                  severity_badge_class(cause["severity"])
                ]}>
                  {cause["severity"]}
                </span>
              </div>
              <p class="mt-2 text-sm leading-6 text-base-content/65">{cause["details"]}</p>
              <ul class="mt-3 space-y-1.5">
                <%= for evidence <- cause["evidence"] do %>
                  <li class="flex gap-2 text-xs leading-5 text-base-content/55">
                    <span class="mt-2 h-1 w-1 shrink-0 rounded-full bg-base-content/35"></span>
                    <span>{evidence}</span>
                  </li>
                <% end %>
              </ul>
            </article>
          <% end %>
        </div>
      <% end %>

      <%= if @analysis["player_readouts"] != [] do %>
        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Player Readouts
          </p>
          <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <%= for readout <- @analysis["player_readouts"] do %>
              <article
                id={"win-loss-player-#{readout["player_id"]}"}
                class="rounded-xl border border-base-300 bg-base-100/60 p-4"
              >
                <div class="flex items-start justify-between gap-3">
                  <h3 class="text-lg font-bold tracking-tight">{readout["player_name"]}</h3>
                  <span class={[
                    "rounded-md border px-2 py-0.5 text-xs font-bold capitalize",
                    trend_badge_class(readout["trend"])
                  ]}>
                    {readout["trend"]}
                  </span>
                </div>
                <p class="mt-2 text-sm leading-6 text-base-content/70">{readout["verdict"]}</p>
                <ul class="mt-3 space-y-1.5">
                  <%= for evidence <- readout["evidence"] do %>
                    <li class="flex gap-2 text-xs leading-5 text-base-content/55">
                      <span class="mt-2 h-1 w-1 shrink-0 rounded-full bg-base-content/35"></span>
                      <span>{evidence}</span>
                    </li>
                  <% end %>
                </ul>
              </article>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @analysis["carry_highlights"] != [] do %>
        <div class="rounded-xl border border-success/30 bg-success/10 p-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-success">Carry Highlights</p>
          <div class="mt-2 grid gap-2 md:grid-cols-2">
            <%= for highlight <- @analysis["carry_highlights"] do %>
              <div>
                <p class="text-sm font-bold">{highlight["title"]}</p>
                <p class="mt-1 text-xs leading-5 text-base-content/60">{highlight["details"]}</p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @analysis["recommendations"] != [] do %>
        <div class="rounded-xl border border-base-300 bg-base-100/60 p-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Adjustments
          </p>
          <ul class="mt-2 space-y-1">
            <%= for recommendation <- @analysis["recommendations"] do %>
              <li class="text-xs leading-5 text-base-content/55">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%= if @analysis["caveats"] != [] do %>
        <div class="rounded-xl border border-base-300 bg-base-100/60 p-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">Caveats</p>
          <ul class="mt-2 space-y-1">
            <%= for caveat <- @analysis["caveats"] do %>
              <li class="text-xs leading-5 text-base-content/55">{caveat}</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  defp confidence_badge_class("high"), do: "border-success/30 bg-success/15 text-success"
  defp confidence_badge_class("medium"), do: "border-warning/30 bg-warning/15 text-warning"
  defp confidence_badge_class(_), do: "border-base-300 bg-base-300/50 text-base-content/60"

  defp position_badge_class("TOP"), do: "bg-amber-500/20 text-amber-400 ring-amber-500/20"

  defp position_badge_class("JUNGLE"),
    do: "bg-emerald-500/20 text-emerald-400 ring-emerald-500/20"

  defp position_badge_class("MIDDLE"), do: "bg-sky-500/20 text-sky-400 ring-sky-500/20"
  defp position_badge_class("BOTTOM"), do: "bg-rose-500/20 text-rose-400 ring-rose-500/20"
  defp position_badge_class("UTILITY"), do: "bg-violet-500/20 text-violet-400 ring-violet-500/20"
  defp position_badge_class(_), do: "bg-base-300/50 text-base-content/50 ring-base-300/50"

  defp position_card_class("TOP"), do: "border-amber-500/30 bg-amber-500/10"
  defp position_card_class("JUNGLE"), do: "border-emerald-500/30 bg-emerald-500/10"
  defp position_card_class("MIDDLE"), do: "border-sky-500/30 bg-sky-500/10"
  defp position_card_class("BOTTOM"), do: "border-rose-500/30 bg-rose-500/10"
  defp position_card_class("UTILITY"), do: "border-violet-500/30 bg-violet-500/10"
  defp position_card_class(_), do: "border-base-300 bg-base-300/50"

  defp severity_badge_class("high"), do: "border-error/30 bg-error/15 text-error"
  defp severity_badge_class("medium"), do: "border-warning/30 bg-warning/15 text-warning"
  defp severity_badge_class(_), do: "border-base-300 bg-base-300/50 text-base-content/60"

  defp trend_badge_class("carrying"), do: "border-success/30 bg-success/15 text-success"
  defp trend_badge_class("struggling"), do: "border-error/30 bg-error/15 text-error"
  defp trend_badge_class("volatile"), do: "border-warning/30 bg-warning/15 text-warning"
  defp trend_badge_class(_), do: "border-base-300 bg-base-300/50 text-base-content/60"

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y at %-I:%M %p UTC")
  end
end
