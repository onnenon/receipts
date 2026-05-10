defmodule Receipts.Riot.AccountIdentityRefresher do
  @moduledoc false

  require Logger

  alias Receipts.LoL.Account

  @riot_client Application.compile_env(:receipts, :riot_client, Receipts.Riot.Client)

  def refresh_all do
    Account
    |> Ash.read!()
    |> Enum.reduce(%{checked: 0, updated: 0, errors: 0}, fn account, summary ->
      case refresh_account(account) do
        :unchanged ->
          %{summary | checked: summary.checked + 1}

        {:updated, _account} ->
          %{summary | checked: summary.checked + 1, updated: summary.updated + 1}

        {:error, _reason} ->
          %{summary | checked: summary.checked + 1, errors: summary.errors + 1}
      end
    end)
    |> tap(fn summary ->
      Logger.info(
        "[AccountIdentityRefresher] checked=#{summary.checked} updated=#{summary.updated} errors=#{summary.errors}"
      )
    end)
  end

  def refresh_account(account) do
    case @riot_client.get_account_by_riot_id(
           account.riot_game_name,
           account.riot_tag_line,
           account.riot_routing
         ) do
      {:ok, %{"puuid" => _} = riot_account} ->
        attrs = refreshed_attrs(account, riot_account)

        if attrs == %{} do
          :unchanged
        else
          updated_account =
            account
            |> Ash.Changeset.for_update(:update, attrs)
            |> Ash.update!()

          if Map.has_key?(attrs, :riot_puuid) do
            Logger.warning(
              "[AccountIdentityRefresher] refreshed #{account.riot_game_name}##{account.riot_tag_line} PUUID and reset sync cursors"
            )
          else
            Logger.info(
              "[AccountIdentityRefresher] refreshed Riot ID casing for #{account.riot_game_name}##{account.riot_tag_line}"
            )
          end

          {:updated, updated_account}
        end

      {:error, :not_found} ->
        Logger.warning(
          "[AccountIdentityRefresher] Riot ID not found: #{account.riot_game_name}##{account.riot_tag_line}"
        )

        {:error, :not_found}

      {:error, reason} ->
        Logger.warning(
          "[AccountIdentityRefresher] failed to refresh #{account.riot_game_name}##{account.riot_tag_line}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp refreshed_attrs(account, %{"puuid" => puuid} = riot_account) do
    game_name = Map.get(riot_account, "gameName", account.riot_game_name)
    tag_line = Map.get(riot_account, "tagLine", account.riot_tag_line)

    %{}
    |> maybe_put(:riot_game_name, game_name, account.riot_game_name)
    |> maybe_put(:riot_tag_line, tag_line, account.riot_tag_line)
    |> maybe_reset_for_puuid(account, puuid)
  end

  defp maybe_put(attrs, _field, value, value), do: attrs
  defp maybe_put(attrs, field, value, _current), do: Map.put(attrs, field, value)

  defp maybe_reset_for_puuid(attrs, %{riot_puuid: puuid}, puuid), do: attrs

  defp maybe_reset_for_puuid(attrs, _account, puuid) do
    Map.merge(attrs, %{
      riot_puuid: puuid,
      newest_synced_at: nil,
      oldest_synced_start: 0,
      oldest_synced_at: nil,
      history_fully_synced: false
    })
  end
end
