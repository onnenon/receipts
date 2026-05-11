defmodule ReceiptsWeb.VersionController do
  use ReceiptsWeb, :controller

  def show(conn, _params) do
    version = System.get_env("RECEIPTS_VERSION") || "unknown"
    built_at = System.get_env("RECEIPTS_BUILT_AT") || "unknown"

    json(conn, %{
      app: "receipts",
      built_at: built_at,
      version: version
    })
  end
end
