defmodule Receipts.AI.Gemini do
  @moduledoc false

  def generate_structured(prompt, schema, opts \\ []) do
    config = Application.get_env(:receipts, :gemini, [])
    api_key = Keyword.get(config, :api_key)
    model = Keyword.get(opts, :model) || Keyword.get(config, :model, "gemini-2.5-flash")

    if blank?(api_key) do
      {:error, :missing_api_key}
    else
      request_generate_content(api_key, model, prompt, schema, opts)
    end
  end

  defp request_generate_content(api_key, model, prompt, schema, opts) do
    url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"

    body = %{
      systemInstruction: %{
        parts: [
          %{
            text:
              Keyword.get(
                opts,
                :system_instruction,
                "Return only factual, compact recommendations grounded in the provided data."
              )
          }
        ]
      },
      contents: [
        %{
          role: "user",
          parts: [%{text: prompt}]
        }
      ],
      generationConfig: %{
        temperature: Keyword.get(opts, :temperature, 0.35),
        responseMimeType: "application/json",
        responseSchema: schema
      }
    }

    request_opts = [
      headers: [{"x-goog-api-key", api_key}],
      json: body,
      connect_options: [timeout: Keyword.get(opts, :connect_timeout, 10_000)],
      receive_timeout: Keyword.get(opts, :receive_timeout, 60_000)
    ]

    case Req.post(url, request_opts) do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        response
        |> response_text()
        |> decode_json()

      {:ok, %{status: status, body: response}} ->
        {:error, {:gemini_request_failed, status, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp response_text(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    parts
    |> Enum.map(&Map.get(&1, "text", ""))
    |> Enum.join("")
  end

  defp response_text(_), do: ""

  defp decode_json(""), do: {:error, :empty_response}

  defp decode_json(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, {:invalid_json, error, text}}
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
