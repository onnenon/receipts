defmodule Receipts.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    log_api_key_status()
    log_gemini_api_key_status()
    log_admin_password_status()

    children =
      [
        ReceiptsWeb.Telemetry,
        Receipts.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:receipts, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:receipts, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Receipts.PubSub},
        {Oban, Application.fetch_env!(:receipts, Oban)},
        ReceiptsWeb.Endpoint
      ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Receipts.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ReceiptsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp log_api_key_status do
    case System.get_env("RIOT_API_KEY") do
      nil ->
        Logger.error("[Config] RIOT_API_KEY is not set — syncs will fail")

      key ->
        trimmed = String.trim(key)

        if trimmed != key do
          Logger.warning(
            "[Config] RIOT_API_KEY has leading/trailing whitespace — this will cause auth failures"
          )
        end

        if String.starts_with?(trimmed, "RGAPI-") and byte_size(trimmed) == 42 do
          prefix = String.slice(trimmed, 0, 11)
          Logger.info("[Config] RIOT_API_KEY loaded: #{prefix}... (#{byte_size(trimmed)} bytes)")
        else
          Logger.error(
            "[Config] RIOT_API_KEY looks malformed (expected 'RGAPI-' + 36 char UUID, got #{byte_size(trimmed)} bytes)"
          )
        end
    end
  end

  defp log_admin_password_status do
    case Application.get_env(:receipts, :admin_password) || System.get_env("ADMIN_PASSWORD") do
      nil ->
        Logger.error("[Config] ADMIN_PASSWORD is not set — admin views will remain locked")

      password ->
        Logger.info("[Config] ADMIN_PASSWORD loaded (#{byte_size(password)} bytes)")
    end
  end

  defp log_gemini_api_key_status do
    api_key =
      :receipts
      |> Application.get_env(:gemini, [])
      |> Keyword.get(:api_key)

    case api_key do
      nil ->
        Logger.warning("[Config] GEMINI_API_KEY is not set — comp suggestions will fail")

      key ->
        trimmed = String.trim(key)

        if trimmed != key do
          Logger.warning(
            "[Config] GEMINI_API_KEY has leading/trailing whitespace — this will cause auth failures"
          )
        end

        Logger.info("[Config] GEMINI_API_KEY loaded (#{byte_size(trimmed)} bytes)")
    end
  end

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") != nil
  end
end
