defmodule ReceiptsWeb.PageControllerTest do
  use ReceiptsWeb.ConnCase

  test "GET / renders landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Browse Receipts"
    assert html_response(conn, 200) =~ "Login"
  end

  test "GET / hides login when already authenticated", %{conn: conn} do
    conn =
      conn
      |> log_in_admin()
      |> recycle()
      |> get(~p"/")

    response = html_response(conn, 200)
    assert response =~ "Browse Receipts"
    assert response =~ "Admin"
    refute response =~ "Login"
  end

  test "GET /receipts redirects to player selection", %{conn: conn} do
    conn = get(conn, ~p"/receipts")
    assert redirected_to(conn) == ~p"/players"
  end
end
