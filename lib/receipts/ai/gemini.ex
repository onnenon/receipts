defmodule Receipts.AI.Gemini do
  @moduledoc false

  require Logger

  def generate_structured(prompt, schema, opts \\ []) do
    config = Application.get_env(:receipts, :gemini, [])
    api_key = Keyword.get(config, :api_key)
    model = Keyword.get(opts, :model) || Keyword.get(config, :model, "gemini-2.5-flash")

    if blank?(api_key) do
      Logger.warning("Gemini request skipped: missing API key")
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

    started_at = System.monotonic_time()
    prompt_bytes = byte_size(prompt)

    Logger.info(
      "Gemini request started model=#{model} prompt_bytes=#{prompt_bytes} " <>
        "connect_timeout=#{request_opts[:connect_options][:timeout]} " <>
        "receive_timeout=#{request_opts[:receive_timeout]}"
    )

    case Req.post(url, request_opts) do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        duration_ms = duration_ms(started_at)
        text = response_text(response)

        Logger.info(
          "Gemini request succeeded model=#{model} status=#{status} duration_ms=#{duration_ms} " <>
            "response_text_bytes=#{byte_size(text)}"
        )

        case decode_json(text) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, reason} = error ->
            Logger.warning(
              "Gemini response decode failed model=#{model} duration_ms=#{duration_ms} " <>
                "reason=#{format_reason(reason)}"
            )

            error
        end

      {:ok, %{status: status, body: response}} ->
        Logger.warning(
          "Gemini request failed model=#{model} status=#{status} duration_ms=#{duration_ms(started_at)}"
        )

        {:error, {:gemini_request_failed, status, response}}

      {:error, reason} ->
        Logger.error(
          "Gemini request error model=#{model} duration_ms=#{duration_ms(started_at)} " <>
            "reason=#{format_reason(reason)}"
        )

        {:error, reason}
    end
  end

  defp duration_ms(started_at) do
    (System.monotonic_time() - started_at)
    |> System.convert_time_unit(:native, :millisecond)
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

  defp format_reason({:invalid_json, error, _text}), do: inspect({:invalid_json, error})
  defp format_reason(reason), do: inspect(reason)
end
