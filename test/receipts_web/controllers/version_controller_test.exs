defmodule ReceiptsWeb.VersionControllerTest do
  use ReceiptsWeb.ConnCase

  test "GET /version returns the release version", %{conn: conn} do
    previous = System.get_env("RECEIPTS_VERSION")
    previous_built_at = System.get_env("RECEIPTS_BUILT_AT")

    System.put_env("RECEIPTS_VERSION", "abc123")
    System.put_env("RECEIPTS_BUILT_AT", "2026-05-11T15:00:00Z")

    on_exit(fn ->
      if previous do
        System.put_env("RECEIPTS_VERSION", previous)
      else
        System.delete_env("RECEIPTS_VERSION")
      end

      if previous_built_at do
        System.put_env("RECEIPTS_BUILT_AT", previous_built_at)
      else
        System.delete_env("RECEIPTS_BUILT_AT")
      end
    end)

    conn = get(conn, ~p"/version")

    assert json_response(conn, 200) == %{
             "app" => "receipts",
             "built_at" => "2026-05-11T15:00:00Z",
             "version" => "abc123"
           }
  end
end
