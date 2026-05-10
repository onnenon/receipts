defmodule ReceiptsWeb.PageControllerTest do
  use ReceiptsWeb.ConnCase

  test "GET / renders player select page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Select a Player"
  end
end
