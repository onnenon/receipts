defmodule ReceiptsWeb.Router do
  use ReceiptsWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:load_admin_authenticated)
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

    get("/login", AdminSessionController, :new)
    post("/login", AdminSessionController, :create)
    get("/admin/login", AdminSessionController, :new)
    post("/admin/login", AdminSessionController, :create)

    live_session :default, on_mount: {ReceiptsWeb.AdminAuth, :assign_admin_authenticated} do
      live("/", PlayerSelectLive, :index)
      live("/players", PlayerLive, :show)
      live("/players/:id", PlayerLive, :show)
      live("/receipts", ReceiptsLive, :index)
    end

    live_session :admin, on_mount: {ReceiptsWeb.AdminAuth, :ensure_authenticated} do
      live("/admin/players", Admin.PlayersLive, :index)
      live("/admin/players/:id", Admin.PlayerDetailLive, :show)
    end
  end

  scope "/", ReceiptsWeb do
    pipe_through(:api)

    get("/version", VersionController, :show)
  end

  if Application.compile_env(:receipts, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: ReceiptsWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  defp load_admin_authenticated(conn, _opts) do
    Plug.Conn.assign(conn, :admin_authenticated, ReceiptsWeb.AdminAuth.authenticated_conn?(conn))
  end
end
