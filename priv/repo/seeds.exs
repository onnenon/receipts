alias Receipts.LoL.{Player, Account}
alias Receipts.Riot.Client

defmodule Seeds do
  require Ash.Query

  def ensure_player(name, game_name, tag_line, region, routing) do
    existing =
      Player
      |> Ash.Query.filter(name == ^name)
      |> Ash.read!()

    player =
      case existing do
        [] ->
          IO.puts("Creating player: #{name}")

          Player
          |> Ash.Changeset.for_create(:create, %{name: name})
          |> Ash.create!()

        [player | _] ->
          IO.puts("Player already exists: #{name}")
          player
      end

    ensure_account(player, game_name, tag_line, region, routing)
  end

  def ensure_account(player, game_name, tag_line, region, routing) do
    existing =
      Account
      |> Ash.Query.filter(player_id == ^player.id)
      |> Ash.read!()

    if existing == [] do
      IO.puts("  Looking up #{game_name}##{tag_line} from Riot API...")

      case Client.get_account_by_riot_id(game_name, tag_line, routing) do
        {:ok, %{"puuid" => puuid}} ->
          Account
          |> Ash.Changeset.for_create(:create, %{
            player_id: player.id,
            riot_puuid: puuid,
            riot_game_name: game_name,
            riot_tag_line: tag_line,
            riot_region: region,
            riot_routing: routing
          })
          |> Ash.create!()

          IO.puts("  Account created: #{game_name}##{tag_line}")

        {:error, :not_found} ->
          IO.puts("  Riot ID not found: #{game_name}##{tag_line}")

        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end
    else
      IO.puts("  Account already exists for #{player.name}, skipping.")
    end
  end
end

Seeds.ensure_player("koozie", "koozie", "0000", "na1", "americas")
Seeds.ensure_player("TheDaddyDH", "TheDaddyDH", "Doob", "na1", "americas")
