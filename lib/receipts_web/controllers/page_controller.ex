defmodule ReceiptsWeb.PageController do
  use ReceiptsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
