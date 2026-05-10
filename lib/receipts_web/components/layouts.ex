defmodule ReceiptsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ReceiptsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates("layouts/*")

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"
  )

  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-50 border-b border-base-300 bg-base-100/90 backdrop-blur-md">
      <div class="mx-auto flex min-h-16 max-w-6xl flex-col gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <a href="/" class="flex items-center gap-2.5 font-bold tracking-tight text-base-content transition hover:text-primary">
          <span class="grid h-8 w-8 place-items-center rounded-lg bg-primary text-primary-content shadow-sm">
            <.icon name="hero-document-chart-bar-mini" class="h-5 w-5" />
          </span>
          Receipts
        </a>
        <nav class="flex items-center gap-2 overflow-x-auto">
          <a href="/receipts" class="rounded-lg px-3 py-2 text-sm font-medium text-base-content/65 transition hover:bg-base-200 hover:text-base-content">
            Receipts
          </a>
          <a href="/admin/players" class="rounded-lg px-3 py-2 text-sm font-medium text-base-content/65 transition hover:bg-base-200 hover:text-base-content">
            Players
          </a>
          <.theme_toggle />
        </nav>
      </div>
    </header>

    <main class="mx-auto max-w-6xl px-4 py-6 sm:px-6 sm:py-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border border-base-300 bg-base-200 p-0.5">
      <div class="absolute left-0.5 h-8 w-8 rounded-full border border-base-300 bg-base-100 shadow-sm [[data-theme=light]_&]:left-[2.25rem] [[data-theme=dark]_&]:left-[4.25rem] transition-[left]" />

      <button
        class="relative z-10 grid h-8 w-8 cursor-pointer place-items-center"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative z-10 grid h-8 w-8 cursor-pointer place-items-center"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative z-10 grid h-8 w-8 cursor-pointer place-items-center"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
