defmodule ReceiptsWeb.AdminSessionController do
  use ReceiptsWeb, :controller

  alias ReceiptsWeb.AdminAuth

  @default_return_to "/admin/players"

  def new(conn, params) do
    if AdminAuth.authenticated_conn?(conn) do
      redirect(conn, to: @default_return_to)
    else
      render(conn, :new, return_to: return_to(params))
    end
  end

  def create(conn, %{"admin_password" => password} = params) do
    return_to = return_to(params)

    if AdminAuth.password_valid?(password) do
      conn
      |> configure_session(renew: true)
      |> put_session(:admin_authenticated, true)
      |> redirect(to: return_to)
    else
      conn
      |> put_flash(:error, "Invalid admin password.")
      |> render(:new, return_to: return_to)
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid admin password.")
    |> render(:new, return_to: @default_return_to)
  end

  defp return_to(%{"return_to" => <<"/", _::binary>> = path}), do: path
  defp return_to(_params), do: @default_return_to
end
