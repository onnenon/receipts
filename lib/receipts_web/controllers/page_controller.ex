defmodule ReceiptsWeb.PageController do
  use ReceiptsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def receipts(conn, _params) do
    redirect(conn, to: ~p"/players")
  end
end
