defmodule ReceiptsWeb.AIComponents do
  use Phoenix.Component

  attr(:suggestion, :map, required: true)
  attr(:generated_at, :any, default: nil)
  attr(:id, :string, required: true)
  attr(:title, :string, default: "Comp Result")
  attr(:subtitle, :string, default: nil)
  slot(:actions)

  def comp_suggestion_report(assigns) do
    ~H"""
    <section id={@id} class="rounded-xl border border-secondary/30 bg-secondary/10 p-4">
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-sm font-extrabold uppercase tracking-wide text-secondary">{@title}</p>
          <p :if={@subtitle} class="mt-0.5 text-xs leading-5 text-base-content/55">
            {@subtitle}
          </p>
        </div>
        {render_slot(@actions)}
      </div>

      <.comp_suggestion_result suggestion={@suggestion} generated_at={@generated_at} />
    </section>
    """
  end

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
  attr(:id, :string, required: true)
  attr(:title, :string, default: "Analysis Result")
  attr(:subtitle, :string, default: nil)
  slot(:actions)

  def win_loss_analysis_report(assigns) do
    ~H"""
    <section id={@id} class="rounded-xl border border-secondary/30 bg-secondary/10 p-4">
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-sm font-extrabold uppercase tracking-wide text-secondary">{@title}</p>
          <p :if={@subtitle} class="mt-0.5 text-xs leading-5 text-base-content/55">
            {@subtitle}
          </p>
        </div>
        {render_slot(@actions)}
      </div>

      <.win_loss_analysis_result analysis={@analysis} generated_at={@generated_at} />
    </section>
    """
  end

  attr(:analysis, :map, required: true)
  attr(:generated_at, :any, default: nil)

  def win_loss_analysis_result(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="rounded-xl border border-base-300 bg-base-100/55 p-4 shadow-sm">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-primary">Verdict</p>
            <p class="mt-2 max-w-4xl text-sm leading-6 text-base-content/75">
              {@analysis["summary"]}
            </p>
            <p :if={@generated_at} class="mt-2 text-xs text-base-content/40">
              Generated {format_datetime(@generated_at)}
            </p>
          </div>
          <span class={[
            "inline-flex shrink-0 items-center rounded-lg border px-2.5 py-1 text-xs font-bold capitalize",
            confidence_badge_class(@analysis["confidence"])
          ]}>
            Evidence: {@analysis["confidence"]}
          </span>
        </div>
      </div>

      <div class="grid gap-3 lg:grid-cols-2">
        <.analysis_insight_column
          id="win-loss-went-well"
          title="What Went Well"
          tone="good"
          insights={@analysis["went_well"]}
        />
        <.analysis_insight_column
          id="win-loss-went-poorly"
          title="What Went Poorly"
          tone="bad"
          insights={@analysis["went_poorly"]}
        />
      </div>

      <%= if @analysis["receipts"] != [] do %>
        <div id="win-loss-receipts" class="space-y-3">
          <div class="rounded-lg border border-primary/25 bg-primary/10 px-3 py-2">
            <p class="text-sm font-extrabold uppercase tracking-wide text-primary">Receipts</p>
            <p class="mt-0.5 text-xs leading-5 text-base-content/55">
              Specific games and stat lines behind the read.
            </p>
          </div>
          <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <%= for receipt <- @analysis["receipts"] do %>
              <article class="rounded-xl border border-primary/20 bg-base-100/60 p-4 shadow-sm">
                <div class="flex items-start justify-between gap-3">
                  <p class="text-sm font-bold">{receipt["label"]}</p>
                  <span class="rounded-md border border-primary/20 bg-primary/10 px-2 py-0.5 text-xs font-bold text-primary">
                    {receipt["result"]}
                  </span>
                </div>
                <p class="mt-2 text-xs font-semibold uppercase tracking-wide text-base-content/45">
                  {[receipt["player_name"], receipt["champion"], receipt["statline"]]
                  |> Enum.reject(&(&1 == ""))
                  |> Enum.join(" · ")}
                </p>
                <p class="mt-2 text-sm leading-6 text-base-content/65">{receipt["takeaway"]}</p>
              </article>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @analysis["player_readouts"] != [] do %>
        <div class="space-y-3">
          <div class="rounded-lg border border-info/25 bg-info/10 px-3 py-2">
            <p class="text-sm font-extrabold uppercase tracking-wide text-info">Player Readouts</p>
            <p class="mt-0.5 text-xs leading-5 text-base-content/55">
              Individual good, bad, and best receipt.
            </p>
          </div>
          <div class="grid gap-3 md:grid-cols-2">
            <%= for readout <- @analysis["player_readouts"] do %>
              <article
                id={"win-loss-player-#{readout["player_id"]}"}
                class="rounded-xl border border-base-300 bg-base-100/60 p-4 shadow-sm"
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

                <div class="mt-3 space-y-3 text-sm leading-6">
                  <p :if={readout["good"] != ""} class="text-base-content/70">
                    <span class="font-bold text-primary">Went well:</span> {readout["good"]}
                  </p>
                  <p :if={readout["bad"] != ""} class="text-base-content/70">
                    <span class="font-bold text-base-content/80">Went poorly:</span> {readout["bad"]}
                  </p>
                  <p :if={readout["receipt"] != ""} class="text-base-content/60">
                    <span class="font-bold text-base-content/70">Receipt:</span> {readout["receipt"]}
                  </p>
                  <p
                    :if={readout["good"] == "" && readout["bad"] == "" && readout["verdict"] != ""}
                    class="text-base-content/70"
                  >
                    {readout["verdict"]}
                  </p>
                </div>

                <ul :if={readout["evidence"] != []} class="mt-3 space-y-1.5">
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

      <%= if @analysis["run_it_back"] != [] do %>
        <div class="rounded-xl border border-warning/25 bg-warning/10 p-3 shadow-sm">
          <p class="text-sm font-extrabold uppercase tracking-wide text-warning">Run It Back</p>
          <ul class="mt-2 space-y-1">
            <%= for recommendation <- @analysis["run_it_back"] do %>
              <li class="text-xs leading-5 text-base-content/60">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%= if @analysis["caveats"] != [] do %>
        <details class="rounded-xl border border-base-300 bg-base-100/60 p-3 shadow-sm">
          <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Caveats
          </summary>
          <ul class="mt-2 space-y-1">
            <%= for caveat <- @analysis["caveats"] do %>
              <li class="text-xs leading-5 text-base-content/55">{caveat}</li>
            <% end %>
          </ul>
        </details>
      <% end %>
    </div>
    """
  end

  attr(:analysis, :map, required: true)
  attr(:generated_at, :any, default: nil)
  attr(:id, :string, required: true)
  attr(:title, :string, default: "Will They Run It Down?")
  attr(:subtitle, :string, default: nil)
  slot(:actions)

  def run_it_down_analysis_report(assigns) do
    ~H"""
    <section id={@id} class="rounded-xl border border-warning/30 bg-warning/10 p-4">
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-sm font-extrabold uppercase tracking-wide text-warning">{@title}</p>
          <p :if={@subtitle} class="mt-0.5 text-xs leading-5 text-base-content/55">
            {@subtitle}
          </p>
        </div>
        {render_slot(@actions)}
      </div>

      <.run_it_down_analysis_result analysis={@analysis} generated_at={@generated_at} />
    </section>
    """
  end

  attr(:analysis, :map, required: true)
  attr(:generated_at, :any, default: nil)

  def run_it_down_analysis_result(assigns) do
    assigns = assign(assigns, :carry_score, carry_score(assigns.analysis["carry_score"]))

    ~H"""
    <div class="space-y-4">
      <div class="rounded-xl border border-base-300 bg-base-100/60 p-4 shadow-sm">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <p class="text-xl font-black tracking-tight">{@analysis["verdict"]}</p>
              <span class={[
                "rounded-lg border px-2.5 py-1 text-xs font-bold capitalize",
                confidence_badge_class(@analysis["confidence"])
              ]}>
                {@analysis["confidence"]} confidence
              </span>
            </div>
            <p class="mt-2 max-w-4xl text-sm leading-6 text-base-content/70">
              {@analysis["summary"]}
            </p>
            <p :if={@generated_at} class="mt-2 text-xs text-base-content/40">
              Generated {format_datetime(@generated_at)}
            </p>
          </div>

          <div class="w-full shrink-0 lg:w-80">
            <div class="flex items-end justify-between gap-3">
              <span class="text-xs font-extrabold uppercase tracking-wide text-error">Feed</span>
              <div class="text-center">
                <p class={["text-3xl font-black", carry_score_text_class(@carry_score)]}>
                  {@carry_score}
                </p>
                <p class="text-xs font-bold text-base-content/45">{@analysis["risk_label"]}</p>
              </div>
              <span class="text-xs font-extrabold uppercase tracking-wide text-success">Carry</span>
            </div>
            <div class="mt-3 h-3 overflow-hidden rounded-full border border-base-300 bg-base-300">
              <div
                class={["h-full rounded-full transition-all", carry_score_bar_class(@carry_score)]}
                style={"width: #{@carry_score}%"}
              >
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="grid gap-3 lg:grid-cols-2">
        <.run_it_down_list
          id="run-it-down-evidence"
          title="Receipts"
          items={@analysis["evidence"]}
          tone="primary"
        />
        <.run_it_down_list
          id="run-it-down-similar-champs"
          title="Similar Champ Read"
          items={@analysis["similar_champ_notes"]}
          tone="info"
        />
      </div>

      <%= if @analysis["advice"] != [] do %>
        <div class="rounded-xl border border-success/25 bg-success/10 p-3 shadow-sm">
          <p class="text-sm font-extrabold uppercase tracking-wide text-success">Lock-In Notes</p>
          <ul class="mt-2 space-y-1">
            <%= for item <- @analysis["advice"] do %>
              <li class="text-xs leading-5 text-base-content/60">{item}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%= if @analysis["caveats"] != [] do %>
        <details class="rounded-xl border border-base-300 bg-base-100/60 p-3 shadow-sm">
          <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Caveats
          </summary>
          <ul class="mt-2 space-y-1">
            <%= for caveat <- @analysis["caveats"] do %>
              <li class="text-xs leading-5 text-base-content/55">{caveat}</li>
            <% end %>
          </ul>
        </details>
      <% end %>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:items, :list, required: true)
  attr(:tone, :string, required: true)

  defp run_it_down_list(assigns) do
    ~H"""
    <section :if={@items != []} id={@id} class="rounded-xl border border-base-300 bg-base-100/60 p-4 shadow-sm">
      <p class={[
        "text-sm font-extrabold uppercase tracking-wide",
        if(@tone == "info", do: "text-info", else: "text-primary")
      ]}>
        {@title}
      </p>
      <ul class="mt-3 space-y-2">
        <%= for item <- @items do %>
          <li class="flex gap-2 text-sm leading-6 text-base-content/65">
            <span class={[
              "mt-2 h-1.5 w-1.5 shrink-0 rounded-full",
              if(@tone == "info", do: "bg-info", else: "bg-primary")
            ]}>
            </span>
            <span>{item}</span>
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:tone, :string, required: true)
  attr(:insights, :list, required: true)

  defp analysis_insight_column(assigns) do
    ~H"""
    <section :if={@insights != []} id={@id} class="space-y-3">
      <div class={[
        "rounded-lg border px-3 py-2",
        analysis_heading_class(@tone)
      ]}>
        <p class={[
          "text-sm font-extrabold uppercase tracking-wide",
          analysis_heading_text_class(@tone)
        ]}>
          {@title}
        </p>
        <p class="mt-0.5 text-xs leading-5 text-base-content/55">
          {analysis_heading_subtitle(@tone)}
        </p>
      </div>
      <div class="space-y-3">
        <%= for insight <- @insights do %>
          <article class={[
            "rounded-xl border bg-base-100/60 p-4 shadow-sm",
            analysis_card_class(@tone)
          ]}>
            <div class="flex items-start justify-between gap-3">
              <h3 class="text-sm font-bold">{insight["title"]}</h3>
              <span class={[
                "rounded-md border px-2 py-0.5 text-xs font-bold",
                evidence_badge_class(insight["evidence_strength"])
              ]}>
                {evidence_strength_label(insight["evidence_strength"])}
              </span>
            </div>
            <p class="mt-2 text-sm leading-6 text-base-content/65">{insight["details"]}</p>
            <ul :if={insight["evidence"] != []} class="mt-3 space-y-1.5">
              <%= for evidence <- insight["evidence"] do %>
                <li class="flex gap-2 text-xs leading-5 text-base-content/55">
                  <span class="mt-2 h-1 w-1 shrink-0 rounded-full bg-base-content/35"></span>
                  <span>{evidence}</span>
                </li>
              <% end %>
            </ul>
          </article>
        <% end %>
      </div>
    </section>
    """
  end

  defp confidence_badge_class("high"), do: "border-success/30 bg-success/15 text-success"
  defp confidence_badge_class("medium"), do: "border-primary/25 bg-primary/10 text-primary"
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

  defp analysis_card_class("good"), do: "border-primary/20"
  defp analysis_card_class(_), do: "border-error/20"

  defp analysis_heading_class("good"), do: "border-success/25 bg-success/10"
  defp analysis_heading_class(_), do: "border-error/25 bg-error/10"

  defp analysis_heading_text_class("good"), do: "text-success"
  defp analysis_heading_text_class(_), do: "text-error"

  defp analysis_heading_subtitle("good"), do: "Strengths, carry signs, and games that held up."

  defp analysis_heading_subtitle(_),
    do: "Recurring issues and games where the pattern broke down."

  defp evidence_badge_class("high"), do: "border-primary/25 bg-primary/10 text-primary"
  defp evidence_badge_class("medium"), do: "border-base-300 bg-base-300/50 text-base-content/65"
  defp evidence_badge_class(_), do: "border-base-300 bg-base-100/70 text-base-content/45"

  defp evidence_strength_label("high"), do: "Strong evidence"
  defp evidence_strength_label("medium"), do: "Some evidence"
  defp evidence_strength_label(_), do: "Thin evidence"

  defp trend_badge_class("carrying"), do: "border-success/30 bg-success/15 text-success"
  defp trend_badge_class("struggling"), do: "border-error/30 bg-error/15 text-error"
  defp trend_badge_class("volatile"), do: "border-warning/30 bg-warning/15 text-warning"
  defp trend_badge_class(_), do: "border-base-300 bg-base-300/50 text-base-content/60"

  defp carry_score(score) when is_integer(score), do: score |> max(0) |> min(100)
  defp carry_score(score) when is_float(score), do: score |> round() |> carry_score()

  defp carry_score(score) when is_binary(score) do
    case Integer.parse(score) do
      {parsed, _rest} -> carry_score(parsed)
      :error -> 50
    end
  end

  defp carry_score(_score), do: 50

  defp carry_score_text_class(score) when score < 35, do: "text-error"
  defp carry_score_text_class(score) when score < 65, do: "text-warning"
  defp carry_score_text_class(_score), do: "text-success"

  defp carry_score_bar_class(score) when score < 35, do: "bg-error"
  defp carry_score_bar_class(score) when score < 65, do: "bg-warning"
  defp carry_score_bar_class(_score), do: "bg-success"

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y at %-I:%M %p UTC")
  end
end
