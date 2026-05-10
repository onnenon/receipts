defmodule ReceiptsWeb.Router do
  use ReceiptsWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ReceiptsWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", ReceiptsWeb do
    pipe_through(:browser)

    live_session :default do
      live("/", PlayerSelectLive, :index)
      live("/players/:id", PlayerLive, :show)
      live("/admin/players", Admin.PlayersLive, :index)
      live("/admin/players/:id", Admin.PlayerDetailLive, :show)
      live("/receipts", ReceiptsLive, :index)
    end
  end

  if Application.compile_env(:receipts, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: ReceiptsWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
