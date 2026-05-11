defmodule ReceiptsWeb.PlayerSelectLiveTest do
  use ReceiptsWeb.ConnCase

  require Ash.Query

  alias Receipts.AI.CompSuggestion, as: CompSuggestionService
  alias Receipts.LoL.{Account, Champion, CompSuggestionCache, Match, MatchParticipant, Player}

  test "selects multiple players before navigating to receipts", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#player-selection-form")
    assert has_element?(view, "#player-tile-#{player_a.id}")
    assert has_element?(view, "#player-tile-#{player_b.id}")

    view
    |> form("#player-selection-form", %{"player_ids" => [player_a.id, player_b.id]})
    |> render_submit()

    player_ids = "#{player_a.id},#{player_b.id}"
    assert_redirect(view, ~p"/players?ids=#{player_ids}")
  end

  test "comparison page shows per-player result columns from shared games only", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")

    account_a = create_account(player_a, "A")
    account_b = create_account(player_b, "B")
    ahri = create_champion("Ahri", 103)

    shared_match = create_match("shared", ~U[2026-05-10 12:00:00Z])
    solo_match = create_match("solo", ~U[2026-05-10 13:00:00Z])

    create_participant(account_a, shared_match, ahri, true, kills: 6)
    create_participant(account_b, shared_match, ahri, false, kills: 2)
    create_participant(account_a, solo_match, ahri, true, kills: 20)

    player_ids = "#{player_a.id},#{player_b.id}"
    {:ok, view, _html} = live(conn, ~p"/players?ids=#{player_ids}")

    assert has_element?(view, "#player-comparison-#{player_a.id}", "Koozie")
    assert has_element?(view, "#player-comparison-#{player_b.id}", "Kupo")
    assert has_element?(view, "#player-comparison-#{player_a.id}", "100.0%")
    assert has_element?(view, "#player-comparison-#{player_b.id}", "0.0%")

    view |> element("#champ-tile-#{player_a.id}-Ahri") |> render_click()
    view |> element("#champ-tile-#{player_b.id}-Ahri") |> render_click()

    assert has_element?(view, "#receipts-result-#{player_a.id}", "6/1/3")
    assert has_element?(view, "#receipts-result-#{player_b.id}", "2/1/3")
    refute has_element?(view, "#receipts-result-#{player_a.id}", "20/1/3")
  end

  test "comp suggestion button is admin only", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")

    player_ids = "#{player_a.id},#{player_b.id}"

    {:ok, view, _html} = live(conn, ~p"/players?ids=#{player_ids}")
    refute has_element?(view, "#suggest-comp-button")

    admin_conn = log_in_admin(conn)
    {:ok, admin_view, _html} = live(admin_conn, ~p"/players?ids=#{player_ids}")
    assert has_element?(admin_view, "#suggest-comp-button")

    html = admin_view |> element("#suggest-comp-button") |> render_click()
    assert html =~ "Generating..."
    assert has_element?(admin_view, "#suggest-comp-button[disabled]")
    assert has_element?(admin_view, "#comp-suggestion-loading")

    render_async(admin_view)

    assert has_element?(admin_view, "#comp-suggestion-result", "Koozie should play mid")
    assert has_element?(admin_view, "#comp-suggestion-result", "he is reliable")
    assert has_element?(admin_view, "#comp-suggestion-result", "Kupo")
    assert has_element?(admin_view, "#comp-suggestion-result", "Recent mid: 24 games")
    assert has_element?(admin_view, "#comp-suggestion-result", "Recent jungle: 14 games")
    assert has_element?(admin_view, "#comp-suggestion-result", "Recent Jax: 2 games")
    assert has_element?(admin_view, "#comp-suggestion-result", "Safer lane setup")
    assert has_element?(admin_view, "#comp-suggestion-result", "Support")
    assert has_element?(admin_view, "#comp-suggestion-result", "his recent support games")
    refute has_element?(admin_view, "#comp-suggestion-result", "recent_non_shared_positions")
    refute has_element?(admin_view, "#comp-suggestion-result", "Recent non-shared games")
    refute has_element?(admin_view, "#comp-suggestion-result", "Utility")
    refute has_element?(admin_view, "#comp-suggestion-result", "she")
    refute has_element?(admin_view, "#comp-suggestion-result", "Her")
  end

  test "admin comparison page loads a fresh cached comp suggestion", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")
    player_ids = [player_a.id, player_b.id]

    create_comp_suggestion(player_ids, DateTime.utc_now(), "Cached setup is still fresh.")

    admin_conn = log_in_admin(conn)
    {:ok, view, _html} = live(admin_conn, ~p"/players?ids=#{Enum.join(player_ids, ",")}")

    assert has_element?(view, "#comp-suggestion-cache-date", "Cached suggestion generated")
    assert has_element?(view, "#comp-suggestion-result", "Cached setup is still fresh.")
    assert has_element?(view, "#suggest-comp-button", "Generate Again")
  end

  test "older comp suggestions remain viewable from history", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")
    player_ids = [player_a.id, player_b.id]

    stored =
      create_comp_suggestion(
        player_ids,
        DateTime.add(DateTime.utc_now(), -2, :day),
        "Old setup can still be inspected."
      )

    admin_conn = log_in_admin(conn)
    {:ok, view, _html} = live(admin_conn, ~p"/players?ids=#{Enum.join(player_ids, ",")}")

    refute has_element?(view, "#comp-suggestion-result")
    assert has_element?(view, "#toggle-comp-suggestion-history", "History")
    refute has_element?(view, "#comp-suggestion-history")

    view
    |> element("#toggle-comp-suggestion-history")
    |> render_click()

    assert has_element?(view, "#comp-suggestion-history")

    view
    |> element("#view-comp-suggestion-#{stored.id}")
    |> render_click()

    assert has_element?(view, "#comp-suggestion-result", "Old setup can still be inspected.")
    refute has_element?(view, "#comp-suggestion-cache-date")
  end

  test "generating again stores another comp suggestion record", %{conn: conn} do
    player_a = create_player("Koozie")
    player_b = create_player("Kupo")
    player_ids = [player_a.id, player_b.id]

    create_comp_suggestion(player_ids, DateTime.utc_now(), "Cached setup is still fresh.")

    admin_conn = log_in_admin(conn)
    {:ok, view, _html} = live(admin_conn, ~p"/players?ids=#{Enum.join(player_ids, ",")}")

    view |> element("#suggest-comp-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#comp-suggestion-result", "Koozie should play mid")
    assert comp_suggestion_count(player_ids) == 2
  end

  defp create_player(name) do
    Player
    |> Ash.Changeset.for_create(:create, %{name: name, discord_id: unique_id()})
    |> Ash.create!()
  end

  defp create_account(player, suffix) do
    Account
    |> Ash.Changeset.for_create(:create, %{
      riot_puuid: "puuid-#{suffix}-#{unique_id()}",
      riot_game_name: "Tester#{suffix}",
      riot_tag_line: "NA1",
      riot_region: "na1",
      riot_routing: "americas",
      player_id: player.id
    })
    |> Ash.create!()
  end

  defp create_champion(name, riot_id) do
    Champion
    |> Ash.Changeset.for_create(:create, %{
      riot_id: riot_id,
      name: name,
      key: name,
      image: "#{name}.png"
    })
    |> Ash.create!()
  end

  defp create_match(id, game_datetime) do
    Match
    |> Ash.Changeset.for_create(:create, %{
      riot_match_id: "NA1_#{id}_#{unique_id()}",
      game_datetime: game_datetime,
      game_duration_seconds: 1800,
      queue_id: 420,
      queue_type: "ranked_solo",
      raw_info: %{}
    })
    |> Ash.create!()
  end

  defp create_participant(account, match, champion, win, opts) do
    MatchParticipant
    |> Ash.Changeset.for_create(:sync, %{
      account_id: account.id,
      match_id: match.id,
      champion_id: champion.id,
      kills: Keyword.fetch!(opts, :kills),
      deaths: 1,
      assists: 3,
      win: win,
      cs: 100,
      damage_dealt: 1000,
      vision_score: 10,
      position: "MIDDLE",
      items: [],
      game_datetime: match.game_datetime,
      queue_type: match.queue_type,
      raw_participant: %{}
    })
    |> Ash.create!()
  end

  defp create_comp_suggestion(player_ids, generated_at, summary) do
    CompSuggestionCache
    |> Ash.Changeset.for_create(:create, %{
      cache_key: CompSuggestionService.cache_key(player_ids),
      player_ids: player_ids,
      filters: CompSuggestionService.cache_filters(),
      generated_at: generated_at,
      suggestion: %{
        "summary" => summary,
        "confidence" => "medium",
        "recommended_lineup" => [],
        "alternatives" => [],
        "caveats" => []
      }
    })
    |> Ash.create!()
  end

  defp comp_suggestion_count(player_ids) do
    cache_key = CompSuggestionService.cache_key(player_ids)

    CompSuggestionCache
    |> Ash.Query.filter(cache_key == ^cache_key)
    |> Ash.read!()
    |> length()
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
end
