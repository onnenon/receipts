defmodule Receipts.LoL do
  use Ash.Domain

  resources do
    resource(Receipts.LoL.Player)
    resource(Receipts.LoL.Account)
    resource(Receipts.LoL.Champion)
    resource(Receipts.LoL.Match)
    resource(Receipts.LoL.MatchParticipant)
    resource(Receipts.LoL.CompSuggestionCache)
    resource(Receipts.LoL.CompPromptLabRun)
    resource(Receipts.LoL.WinLossAnalysisCache)
    resource(Receipts.LoL.WinLossPromptLabRun)
    resource(Receipts.LoL.RunItDownAnalysisCache)
  end
end
