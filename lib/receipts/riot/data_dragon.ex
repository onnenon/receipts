defmodule Receipts.Riot.DataDragon do
  @moduledoc false

  require Logger

  @versions_url "https://ddragon.leagueoflegends.com/api/versions.json"

  # Fetches the latest champion list from Data Dragon and upserts into the DB.
  def sync_champions do
    with {:ok, version} <- get_latest_version(),
         {:ok, data} <- get_champion_data(version) do
      upsert_champions(data, version)
    end
  end

  defp get_latest_version do
    case Req.get(@versions_url) do
      {:ok, %Req.Response{status: 200, body: [version | _]}} ->
        {:ok, version}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:versions_fetch_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_champion_data(version) do
    url = "https://ddragon.leagueoflegends.com/cdn/#{version}/data/en_US/champion.json"

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:champion_data_fetch_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_champions(data, version) do
    inputs =
      Enum.map(data, fn {_key, champ} ->
        %{
          # "key" in Data Dragon is the numeric ID as a string
          riot_id: String.to_integer(champ["key"]),
          # "id" in Data Dragon is the internal string key (e.g. "Yasuo")
          key: champ["id"],
          name: champ["name"],
          image: champ["image"]["full"]
        }
      end)

    result =
      Ash.bulk_create(inputs, Receipts.LoL.Champion, :create,
        upsert?: true,
        upsert_identity: :unique_riot_id,
        upsert_fields: [:name, :key, :image],
        return_errors?: true
      )

    case result do
      %Ash.BulkResult{status: :success} ->
        Logger.info("DataDragon: synced #{length(inputs)} champions (version #{version})")
        {:ok, length(inputs)}

      %Ash.BulkResult{status: status, errors: errors, error_count: error_count} ->
        Logger.error("DataDragon: sync #{status}, #{error_count} errors: #{inspect(errors)}")
        {:error, {status, errors}}
    end
  end
end
