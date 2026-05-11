defmodule ReceiptsWeb.VersionController do
  use ReceiptsWeb, :controller

  def show(conn, _params) do
    version = System.get_env("RECEIPTS_VERSION") || "unknown"

    json(conn, %{
      app: "receipts",
      version: version
    })
  end
end
