defmodule Receipts.LoL do
  use Ash.Domain

  resources do
    resource(Receipts.LoL.Player)
    resource(Receipts.LoL.Account)
    resource(Receipts.LoL.Champion)
    resource(Receipts.LoL.Match)
    resource(Receipts.LoL.MatchParticipant)
  end
end
