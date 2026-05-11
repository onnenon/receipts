defmodule Receipts.LoggerFormatter do
  @moduledoc false

  def new(opts) do
    {Logger.Formatter, formatter} = Logger.Formatter.new(opts)
    {__MODULE__, formatter}
  end

  def format(event, formatter) do
    event
    |> Logger.Formatter.format(formatter)
    |> IO.iodata_to_binary()
    |> String.trim_trailing("\n")
    |> String.replace(~r/\R\s*/, " ")
    |> Kernel.<>("\n")
  end
end
