defmodule ReceiptsWeb.AdminAuth do
  @login_path "/login"

  def on_mount(:assign_admin_authenticated, _params, session, socket) do
    {:cont,
     Phoenix.LiveView.Utils.assign(socket, :admin_authenticated, authenticated_session?(session))}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    if authenticated_session?(session) do
      {:cont, Phoenix.LiveView.Utils.assign(socket, :admin_authenticated, true)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: @login_path)}
    end
  end

  def authenticated_session?(session) when is_map(session) do
    Map.get(session, "admin_authenticated") == true ||
      Map.get(session, :admin_authenticated) == true
  end

  def authenticated_conn?(conn) do
    Plug.Conn.get_session(conn, :admin_authenticated) == true
  end

  def password_valid?(password) when is_binary(password) do
    case admin_password() do
      stored when is_binary(stored) and byte_size(stored) == byte_size(password) ->
        Plug.Crypto.secure_compare(stored, password)

      _ ->
        false
    end
  end

  def password_valid?(_), do: false

  def admin_password do
    Application.get_env(:receipts, :admin_password) || System.get_env("ADMIN_PASSWORD")
  end
end
