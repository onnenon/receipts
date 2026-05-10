defmodule Receipts.Riot.AccountIdentityRefresherTest do
  use Receipts.DataCase

  alias Receipts.LoL.{Account, Player}
  alias Receipts.Riot.AccountIdentityRefresher
  alias Receipts.RiotClientStub

  setup do
    RiotClientStub.reset()

    player =
      Player
      |> Ash.Changeset.for_create(:create, %{name: "Test Player", discord_id: unique_id()})
      |> Ash.create!()

    account =
      Account
      |> Ash.Changeset.for_create(:create, %{
        riot_puuid: "old-puuid",
        riot_game_name: "tester",
        riot_tag_line: "na1",
        riot_region: "na1",
        riot_routing: "americas",
        player_id: player.id
      })
      |> Ash.create!()

    %{account: account}
  end

  test "changed puuid resets sync cursors", %{account: account} do
    newest_synced_at = ~U[2026-05-10 12:00:00Z]
    oldest_synced_at = ~U[2025-07-22 21:26:40Z]

    account =
      update_account!(account, %{
        newest_synced_at: newest_synced_at,
        oldest_synced_start: 475,
        oldest_synced_at: oldest_synced_at,
        history_fully_synced: true
      })

    RiotClientStub.put_accounts_by_riot_id(fn "tester", "na1", "americas" ->
      {:ok, %{"puuid" => "new-puuid", "gameName" => "Tester", "tagLine" => "NA1"}}
    end)

    assert {:updated, updated_account} = AccountIdentityRefresher.refresh_account(account)

    assert updated_account.riot_puuid == "new-puuid"
    assert updated_account.riot_game_name == "Tester"
    assert updated_account.riot_tag_line == "NA1"
    assert is_nil(updated_account.newest_synced_at)
    assert updated_account.oldest_synced_start == 0
    assert is_nil(updated_account.oldest_synced_at)
    refute updated_account.history_fully_synced
  end

  test "unchanged puuid preserves sync cursors while refreshing canonical riot id casing", %{
    account: account
  } do
    newest_synced_at = ~U[2026-05-10 12:00:00Z]
    oldest_synced_at = ~U[2025-07-22 21:26:40Z]

    account =
      update_account!(account, %{
        newest_synced_at: newest_synced_at,
        oldest_synced_start: 475,
        oldest_synced_at: oldest_synced_at,
        history_fully_synced: true
      })

    RiotClientStub.put_accounts_by_riot_id(fn "tester", "na1", "americas" ->
      {:ok, %{"puuid" => "old-puuid", "gameName" => "Tester", "tagLine" => "NA1"}}
    end)

    assert {:updated, updated_account} = AccountIdentityRefresher.refresh_account(account)

    assert updated_account.riot_puuid == "old-puuid"
    assert updated_account.riot_game_name == "Tester"
    assert updated_account.riot_tag_line == "NA1"
    assert DateTime.compare(updated_account.newest_synced_at, newest_synced_at) == :eq
    assert updated_account.oldest_synced_start == 475
    assert DateTime.compare(updated_account.oldest_synced_at, oldest_synced_at) == :eq
    assert updated_account.history_fully_synced
  end

  defp update_account!(account, attrs) do
    account
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!()
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
