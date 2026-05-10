defmodule Mix.Tasks.Receipts.RefreshPuuids do
  @shortdoc "Re-fetches PUUIDs for all accounts using the current API key"
  @moduledoc """
  PUUIDs issued by the Riot API are encrypted per API key environment (dev vs
  prod/personal). If you switch API keys, stored PUUIDs become invalid and every
  sync job fails with \"Exception decrypting\".

  This task re-fetches each account's PUUID by calling the Riot account lookup
  endpoint with the existing game_name + tag_line, then updates the DB record.

      mix receipts.refresh_puuids
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    accounts = Receipts.LoL.Account |> Ash.read!()

    if accounts == [] do
      Mix.shell().info("No accounts found.")
      :ok
    else
      Mix.shell().info("Refreshing PUUIDs for #{length(accounts)} account(s)...")

      Enum.each(accounts, fn account ->
        tag = "#{account.riot_game_name}##{account.riot_tag_line} (#{account.riot_region})"

        case Receipts.Riot.Client.get_account_by_riot_id(
               account.riot_game_name,
               account.riot_tag_line,
               account.riot_routing
             ) do
          {:ok, %{"puuid" => new_puuid}} when new_puuid == account.riot_puuid ->
            Mix.shell().info("  #{tag} — PUUID unchanged, skipping")

          {:ok, %{"puuid" => new_puuid}} ->
            account
            |> Ash.Changeset.for_update(:update, %{riot_puuid: new_puuid})
            |> Ash.update!()

            Mix.shell().info("  #{tag} — PUUID updated")

          {:error, :not_found} ->
            Mix.shell().error("  #{tag} — Riot account not found (name changed?)")

          {:error, :rate_limited} ->
            Mix.shell().error("  #{tag} — rate limited, try again in a moment")

          {:error, reason} ->
            Mix.shell().error("  #{tag} — failed: #{inspect(reason)}")
        end
      end)

      Mix.shell().info("Done. Run 'mix phx.server' and syncs should resume.")
    end
  end
end
