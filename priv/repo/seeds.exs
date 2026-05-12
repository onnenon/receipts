case Receipts.Riot.DataDragon.sync_champions() do
  {:ok, count} -> IO.puts("Synced #{count} champions from Data Dragon")
  {:error, reason} -> raise "Failed to sync champions from Data Dragon: #{inspect(reason)}"
end
