defmodule ReceiptsWeb.Admin.PlayersLive do
  use ReceiptsWeb, :live_view

  require Ash.Query

  alias AshPhoenix.Form, as: AshForm
  alias Receipts.LoL.Player

  @impl true
  def mount(_params, _session, socket) do
    players =
      Player
      |> Ash.Query.load([:accounts, :oldest_game_date, :newest_game_date])
      |> Ash.read!()

    {:ok,
     socket
     |> stream(:players, players)
     |> assign(:show_modal, false)
     |> assign(:form, new_player_form())}
  end

  @impl true
  def handle_event("show_modal", _, socket) do
    {:noreply, assign(socket, show_modal: true)}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, show_modal: false, form: new_player_form())}
  end

  @impl true
  def handle_event("validate", %{"player" => params}, socket) do
    form = socket.assigns.form.source |> AshForm.validate(params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"player" => params}, socket) do
    case AshForm.submit(socket.assigns.form.source, params: params) do
      {:ok, player} ->
        player_with_accounts =
          Player
          |> Ash.Query.filter(id == ^player.id)
          |> Ash.Query.load([:accounts, :oldest_game_date, :newest_game_date])
          |> Ash.read!()
          |> List.first()

        {:noreply,
         socket
         |> stream_insert(:players, player_with_accounts, at: 0)
         |> assign(show_modal: false, form: new_player_form())
         |> put_flash(:info, "#{player.name} added!")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp new_player_form do
    AshForm.for_create(Player, :create, as: "player", domain: Receipts.LoL) |> to_form()
  end

  defp format_date(nil), do: ""

  defp format_date(dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-primary">Admin</p>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Players</h1>
            <p class="mt-1 text-sm text-base-content/55">
              Link Discord friends to every Riot account they play on.
            </p>
          </div>
          <button
            id="open-new-player"
            phx-click="show_modal"
            class="inline-flex items-center justify-center gap-1.5 rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm transition hover:opacity-90"
          >
            <.icon name="hero-plus-mini" class="h-4 w-4" /> Add Player
          </button>
        </div>

        <div id="players" phx-update="stream" class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
          <div id="players-empty" class="hidden only:flex items-center justify-center py-16 text-base-content/40">
            No players yet. Add one to start collecting receipts.
          </div>
          <%= for {id, player} <- @streams.players do %>
            <div id={id} class="flex flex-col gap-4 border-b border-base-300 px-5 py-4 transition last:border-b-0 hover:bg-base-300/45 sm:flex-row sm:items-center">
              <div class="flex-1 min-w-0">
                <p class="font-semibold truncate">{player.name}</p>
                <p class="text-sm text-base-content/50">
                  {account_summary(player.accounts)}
                  <%= if player.discord_id do %>
                    · Discord: {player.discord_id}
                  <% end %>
                  <%= if player.oldest_game_date do %>
                    · {format_date(player.oldest_game_date)} – {format_date(player.newest_game_date)}
                  <% end %>
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <.link
                  navigate={~p"/players/#{player.id}"}
                  class="rounded-md px-3 py-1.5 text-xs font-medium text-base-content/60 hover:text-base-content border border-base-300 hover:bg-base-300 transition-colors"
                >
                  Receipts
                </.link>
                <.link
                  navigate={~p"/admin/players/#{player.id}"}
                  class="rounded-md px-3 py-1.5 text-xs font-medium text-primary border border-primary/30 hover:bg-primary/10 transition-colors"
                >
                  Manage →
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%= if @show_modal do %>
        <div
          id="new-player-modal"
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm"
        >
          <button
            type="button"
            id="new-player-modal-backdrop"
            class="absolute inset-0"
            phx-click="close_modal"
            aria-label="Close new player form"
          />

          <div
            id="new-player-modal-panel"
            class="relative w-full max-w-md rounded-2xl bg-base-100 p-6 shadow-2xl"
            phx-click-away="close_modal"
          >
            <div class="mb-5 flex items-center justify-between">
              <h2 class="text-lg font-bold">Add Player</h2>
              <button phx-click="close_modal" class="text-base-content/40 hover:text-base-content transition-colors">
                <.icon name="hero-x-mark" class="h-5 w-5" />
              </button>
            </div>

            <.form
              for={@form}
              id="new-player-form"
              phx-change="validate"
              phx-submit="save"
            >
              <div class="space-y-4">
                <.input field={@form[:name]} type="text" label="Name" placeholder="koozie" required />
                <.input
                  field={@form[:discord_id]}
                  type="text"
                  label="Discord ID"
                  placeholder="optional"
                />
              </div>
              <div class="mt-6 flex justify-end gap-3">
                <button
                  type="button"
                  phx-click="close_modal"
                  class="rounded-lg border border-base-300 px-4 py-2 text-sm font-medium hover:bg-base-200 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:opacity-90 transition-opacity phx-submit-loading:opacity-50"
                >
                  Add Player
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp account_summary([]), do: "No accounts"
  defp account_summary([_]), do: "1 account"
  defp account_summary(accounts), do: "#{length(accounts)} accounts"
end
