defmodule ReceiptsWeb.Admin.PlayerDetailLive do
  use ReceiptsWeb, :live_view

  require Ash.Query

  alias Receipts.LoL.{Player, Account, MatchParticipant}
  alias Receipts.Workers.SyncAccount

  @riot_client Application.compile_env(:receipts, :riot_client, Receipts.Riot.Client)

  @regions [
    {"NA", "na1", "americas"},
    {"EUW", "euw1", "europe"},
    {"KR", "kr", "asia"},
    {"EUNE", "eun1", "europe"},
    {"BR", "br1", "americas"},
    {"OCE", "oc1", "sea"},
    {"JP", "jp1", "asia"},
    {"TR", "tr1", "europe"},
    {"LAN", "la1", "americas"},
    {"LAS", "la2", "americas"},
    {"RU", "ru", "europe"}
  ]

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
        {:ok, push_navigate(socket, to: ~p"/admin/players")}

      player ->
        {:ok,
         socket
         |> assign(:player, player)
         |> assign(:total_games, count_total_games(player.accounts))
         |> assign(:show_add_account, false)
         |> assign(:add_account_form, new_add_account_form())
         |> assign(:adding_account, false)
         |> stream(:accounts, player.accounts)}
    end
  end

  @impl true
  def handle_event("toggle_add_account", _, socket) do
    {:noreply,
     assign(socket,
       show_add_account: !socket.assigns.show_add_account,
       add_account_form: new_add_account_form()
     )}
  end

  @impl true
  def handle_event(
        "add_account",
        %{"account" => %{"riot_id" => riot_id, "region" => region}},
        socket
      ) do
    socket = assign(socket, :adding_account, true)

    case parse_riot_id(riot_id) do
      {:ok, game_name, tag_line} ->
        {platform, routing} = region_platform(region)

        case @riot_client.get_account_by_riot_id(game_name, tag_line, routing) do
          {:ok, %{"puuid" => puuid}} ->
            attrs = %{
              player_id: socket.assigns.player.id,
              riot_puuid: puuid,
              riot_game_name: game_name,
              riot_tag_line: tag_line,
              riot_region: platform,
              riot_routing: routing
            }

            case Account |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
              {:ok, account} ->
                %{account_id: account.id}
                |> SyncAccount.new()
                |> Oban.insert!()

                updated_accounts = [account | socket.assigns.player.accounts]

                {:noreply,
                 socket
                 |> assign(
                   adding_account: false,
                   show_add_account: false,
                   add_account_form: new_add_account_form(),
                   total_games: count_total_games(updated_accounts)
                 )
                 |> stream_insert(:accounts, account, at: 0)
                 |> put_flash(:info, "#{game_name}##{tag_line} added. Sync started.")}

              {:error, _changeset} ->
                {:noreply,
                 socket
                 |> assign(:adding_account, false)
                 |> put_flash(:error, "Account already exists or could not be saved.")}
            end

          {:error, :not_found} ->
            {:noreply,
             socket
             |> assign(:adding_account, false)
             |> put_flash(:error, "Riot ID \"#{riot_id}\" not found. Check the name and tag.")}

          {:error, :rate_limited} ->
            {:noreply,
             socket
             |> assign(:adding_account, false)
             |> put_flash(:error, "Riot API rate limited — try again in a moment.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:adding_account, false)
             |> put_flash(:error, "Failed to look up Riot ID.")}
        end

      :error ->
        {:noreply,
         socket
         |> assign(:adding_account, false)
         |> put_flash(:error, "Invalid format — use GameName#Tag (e.g. TheDaddyDH#Doob).")}
    end
  end

  @impl true
  def handle_event("sync_now", %{"account-id" => account_id}, socket) do
    %{account_id: account_id}
    |> SyncAccount.new()
    |> Oban.insert!()

    {:noreply, put_flash(socket, :info, "Sync job enqueued.")}
  end

  defp count_total_games([]), do: 0

  defp count_total_games(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    MatchParticipant
    |> Ash.Query.filter(account_id in ^account_ids)
    |> Ash.count!()
  end

  defp parse_riot_id(riot_id) do
    case String.split(riot_id, "#", parts: 2) do
      [game_name, tag_line] when game_name != "" and tag_line != "" ->
        {:ok, game_name, tag_line}

      _ ->
        :error
    end
  end

  defp region_platform(region) do
    Enum.find_value(@regions, {"na1", "americas"}, fn {label, platform, routing} ->
      if label == region, do: {platform, routing}
    end)
  end

  defp new_add_account_form do
    to_form(%{"riot_id" => "", "region" => "NA"}, as: "account")
  end

  defp region_options do
    Enum.map(@regions, fn {label, _, _} -> {label, label} end)
  end

  defp format_synced_at(nil), do: "Never synced"

  defp format_synced_at(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "Synced just now"
      diff < 3600 -> "Synced #{div(diff, 60)}m ago"
      diff < 86_400 -> "Synced #{div(diff, 3600)}h ago"
      true -> "Synced #{div(diff, 86_400)}d ago"
    end
  end

  defp format_date(nil), do: "N/A"

  defp format_date(dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :region_options, region_options())

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <%!-- Breadcrumb --%>
        <div class="flex items-center gap-2 text-sm text-base-content/50">
          <.link navigate={~p"/admin/players"} class="hover:text-base-content transition-colors">
            Players
          </.link>
          <span>/</span>
          <span class="text-base-content font-medium">{@player.name}</span>
        </div>

        <%!-- Player header --%>
        <div class="flex flex-col gap-4 rounded-xl border border-base-300 bg-base-200 p-5 shadow-sm sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-primary">Player profile</p>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">{@player.name}</h1>
            <p class="mt-1 text-sm text-base-content/50">
              <%= if @player.discord_id do %>
                Discord: {@player.discord_id}
              <% else %>
                No Discord ID set
              <% end %>
            </p>
            <div class="mt-2 flex items-center gap-1.5 text-sm">
              <span class="font-semibold text-base-content">{@total_games}</span>
              <span class="text-base-content/50">total games indexed</span>
              <%= if @player.oldest_game_date do %>
                <span class="text-base-content/30">·</span>
                <span class="text-base-content/50">
                  {format_date(@player.oldest_game_date)} – {format_date(@player.newest_game_date)}
                </span>
              <% end %>
            </div>
          </div>
          <.link
            navigate={~p"/receipts?player_id=#{@player.id}"}
            class="inline-flex items-center justify-center gap-1.5 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm font-medium transition hover:bg-base-300/60"
          >
            View Receipts
            <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
          </.link>
        </div>

        <%!-- Accounts --%>
        <div class="space-y-3">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-lg font-semibold">Accounts</h2>
              <p class="text-sm text-base-content/50">Every linked Riot ID rolls into receipt searches.</p>
            </div>
            <button
              id="toggle-add-account"
              phx-click="toggle_add_account"
              class="inline-flex items-center justify-center gap-1.5 rounded-lg bg-primary/10 px-3 py-2 text-sm font-semibold text-primary transition hover:bg-primary/20"
            >
              <.icon name={if @show_add_account, do: "hero-minus-mini", else: "hero-plus-mini"} class="h-4 w-4" />
              {if @show_add_account, do: "Cancel", else: "Add Account"}
            </button>
          </div>

          <%= if @show_add_account do %>
            <div id="add-account-panel" class="rounded-xl border border-primary/20 bg-base-200 p-5 shadow-sm">
              <h3 class="mb-4 text-sm font-semibold text-base-content/70">Add Riot Account</h3>
              <.form for={@add_account_form} id="add-account-form" phx-submit="add_account">
                <div class="flex flex-col gap-3 sm:flex-row">
                  <div class="flex-1">
                    <.input
                      field={@add_account_form[:riot_id]}
                      type="text"
                      label="Riot ID"
                      placeholder="TheDaddyDH#Doob"
                    />
                  </div>
                  <div class="w-28">
                    <.input
                      field={@add_account_form[:region]}
                      type="select"
                      label="Region"
                      options={@region_options}
                    />
                  </div>
                </div>
                <div class="mt-4">
                  <button
                    type="submit"
                    disabled={@adding_account}
                    class="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-content hover:opacity-90 transition-opacity disabled:opacity-50"
                  >
                    {if @adding_account, do: "Looking up...", else: "Add Account"}
                  </button>
                </div>
              </.form>
            </div>
          <% end %>

          <div id="accounts" phx-update="stream" class="overflow-hidden rounded-xl border border-base-300 bg-base-200 shadow-sm">
            <div id="accounts-empty" class="hidden only:flex items-center justify-center py-10 text-sm text-base-content/40">
              No accounts yet — add one above.
            </div>
            <%= for {id, account} <- @streams.accounts do %>
              <div id={id} class="flex flex-col gap-4 border-b border-base-300 px-5 py-4 last:border-b-0 sm:flex-row sm:items-center">
                <div class="flex-1 min-w-0">
                  <p class="font-semibold">
                    {account.riot_game_name}#{account.riot_tag_line}
                    <span class="ml-2 rounded-md bg-base-300 px-1.5 py-0.5 text-xs font-medium text-base-content/60 uppercase">
                      {account.riot_region}
                    </span>
                  </p>
                  <p class="mt-0.5 text-sm text-base-content/50">
                    {format_synced_at(account.newest_synced_at)}
                    · History:
                    {if account.history_fully_synced,
                      do: "complete ✓",
                      else: "#{account.oldest_synced_start} games indexed"}
                  </p>
                </div>
                <button
                  id={"sync-#{account.id}"}
                  phx-click="sync_now"
                  phx-value-account-id={account.id}
                  class="inline-flex items-center justify-center rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold transition hover:bg-base-300 phx-click-loading:opacity-50"
                >
                  Sync Now
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
