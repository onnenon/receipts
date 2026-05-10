defmodule Receipts.Riot.Client do
  @moduledoc false

  defp api_key do
    key = System.get_env("RIOT_API_KEY") || raise "RIOT_API_KEY not set in environment"
    String.trim(key)
  end

  defp build_req(routing) do
    Req.new(
      base_url: "https://#{routing}.api.riotgames.com",
      headers: [{"X-Riot-Token", api_key()}]
    )
  end

  # Returns account info including puuid for a given Riot ID (game_name#tag_line).
  # routing is the regional value: americas, europe, asia, sea
  def get_account_by_riot_id(game_name, tag_line, routing) do
    encoded_name = URI.encode(game_name, &URI.char_unreserved?/1)
    encoded_tag = URI.encode(tag_line, &URI.char_unreserved?/1)

    build_req(routing)
    |> Req.get(url: "/riot/account/v1/accounts/by-riot-id/#{encoded_name}/#{encoded_tag}")
    |> handle_response()
  end

  # Returns a list of match IDs for a given PUUID.
  # opts: start (index), count (max 100), startTime (epoch seconds), endTime, queue, type
  def get_match_ids(puuid, routing, opts \\ []) do
    build_req(routing)
    |> Req.get(
      url: "/lol/match/v5/matches/by-puuid/#{puuid}/ids",
      params: Map.new(opts)
    )
    |> handle_response()
  end

  # Returns full match detail JSON for a given match ID.
  def get_match(match_id, routing) do
    build_req(routing)
    |> Req.get(url: "/lol/match/v5/matches/#{match_id}")
    |> handle_response()
  end

  # Returns league entries (rank) for a given PUUID.
  # platform is the platform routing value: na1, euw1, kr, etc.
  def get_rank_by_puuid(puuid, platform) do
    build_req(platform)
    |> Req.get(url: "/lol/league/v4/entries/by-puuid/#{puuid}")
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}
  defp handle_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}
  defp handle_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}
end
