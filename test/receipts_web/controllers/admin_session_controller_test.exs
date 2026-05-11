defmodule ReceiptsWeb.AdminSessionControllerTest do
  use ReceiptsWeb.ConnCase

  test "renders the login page", %{conn: conn} do
    conn = get(conn, "/login")

    assert conn.status == 200
  end

  test "logs in with the admin password and protects admin live views", %{conn: conn} do
    conn = log_in_admin(conn)

    assert redirected_to(conn) == "/admin/players"

    {:ok, view, _html} = live(conn, ~p"/admin/players")
    assert has_element?(view, "#players")
  end

  test "rejects admin access without a session", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/players")
  end
end
