defmodule Receipts.PromEx do
  use PromEx, otp_app: :receipts

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: ReceiptsWeb.Router, endpoint: ReceiptsWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Receipts.Repo]},
      {PromEx.Plugins.Oban, queue_poll_interval: 5_000}
    ]
  end
end
