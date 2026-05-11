defmodule ReceiptsWeb.VersionControllerTest do
  use ReceiptsWeb.ConnCase

  test "GET /version returns the release version", %{conn: conn} do
    previous = System.get_env("RECEIPTS_VERSION")
    System.put_env("RECEIPTS_VERSION", "abc123")

    on_exit(fn ->
      if previous do
        System.put_env("RECEIPTS_VERSION", previous)
      else
        System.delete_env("RECEIPTS_VERSION")
      end
    end)

    conn = get(conn, ~p"/version")

    assert json_response(conn, 200) == %{
             "app" => "receipts",
             "version" => "abc123"
           }
  end
end
