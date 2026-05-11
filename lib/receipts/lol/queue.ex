defmodule Receipts.LoL.Queue do
  @moduledoc false

  @queue_map %{
    0 => "custom",
    400 => "normal_draft",
    420 => "ranked_solo",
    430 => "normal_blind",
    440 => "ranked_flex",
    450 => "aram",
    700 => "clash",
    720 => "aram_clash",
    900 => "urf",
    1020 => "one_for_all",
    1300 => "nexus_blitz",
    1400 => "ultimate_spellbook",
    1700 => "arena",
    1900 => "urf",
    2000 => "tutorial",
    2010 => "tutorial",
    2020 => "tutorial"
  }

  @labels %{
    "ranked_solo" => "Ranked Solo/Duo",
    "ranked_flex" => "Ranked Flex",
    "normal_draft" => "Normal Draft",
    "normal_blind" => "Normal Blind",
    "aram" => "ARAM",
    "clash" => "Clash",
    "aram_clash" => "ARAM Clash",
    "urf" => "URF",
    "one_for_all" => "One for All",
    "nexus_blitz" => "Nexus Blitz",
    "ultimate_spellbook" => "Ultimate Spellbook",
    "arena" => "Arena",
    "custom" => "Custom",
    "tutorial" => "Tutorial",
    "other" => "Other"
  }

  # Ordered list of queue types to display in the UI, with their defaults.
  # {type, label, included_by_default?}
  @ui_queues [
    {"ranked_solo", "Ranked Solo/Duo", true},
    {"ranked_flex", "Ranked Flex", false},
    {"normal_draft", "Normal Draft", false},
    {"normal_blind", "Normal Blind", false},
    {"clash", "Clash", false},
    {"aram", "ARAM", false},
    {"urf", "URF", false},
    {"arena", "Arena", false},
    {"one_for_all", "One for All", false},
    {"other", "Other", false}
  ]

  # Queue types that have lane position data from Riot's teamPosition field
  @position_queues ~w(ranked_solo ranked_flex normal_draft normal_blind clash)

  def from_id(queue_id) when is_integer(queue_id) do
    Map.get(@queue_map, queue_id, "other")
  end

  def from_id(_), do: "other"

  def label(queue_type), do: Map.get(@labels, queue_type, queue_type)

  def ui_queues, do: @ui_queues

  def default_queues do
    for {type, _label, true} <- @ui_queues, do: type
  end

  def has_positions?(queue_type), do: queue_type in @position_queues
end
