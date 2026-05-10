defmodule Receipts.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    log_api_key_status()

    children =
      [
        ReceiptsWeb.Telemetry,
        Receipts.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:receipts, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:receipts, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Receipts.PubSub},
        {Oban, Application.fetch_env!(:receipts, Oban)},
        account_identity_refresher_child(),
        ReceiptsWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

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

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") != nil
  end

  defp account_identity_refresher_child do
    if Application.get_env(:receipts, :refresh_account_identities_on_startup, true) do
      {Task, fn -> Receipts.Riot.AccountIdentityRefresher.refresh_all() end}
    end
  end
end
