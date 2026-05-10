defmodule Receipts.Repo do
  use Ecto.Repo,
    otp_app: :receipts,
    adapter: Ecto.Adapters.SQLite3
end
