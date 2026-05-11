defmodule Receipts.LoL.Queue do
  @moduledoc false

  @queue_map %{
    # Custom
    0 => "custom",
    # Normal
    2 => "normal_blind",
    14 => "normal_draft",
    400 => "normal_draft",
    430 => "normal_blind",
    480 => "swiftplay",
    490 => "quickplay",
    # Ranked
    4 => "ranked_solo",
    6 => "ranked_premade",
    42 => "ranked_team",
    410 => "ranked_dynamic",
    420 => "ranked_solo",
    440 => "ranked_flex",
    # ARAM
    65 => "aram",
    100 => "aram",
    450 => "aram",
    2400 => "aram",
    # Clash
    700 => "clash",
    720 => "aram_clash",
    # URF
    76 => "urf",
    83 => "urf",
    318 => "urf",
    900 => "urf",
    1010 => "urf",
    1900 => "urf",
    # Arena
    1700 => "arena",
    1710 => "arena",
    # Swarm
    1810 => "swarm",
    1820 => "swarm",
    1830 => "swarm",
    1840 => "swarm",
    # One for All
    70 => "one_for_all",
    78 => "one_for_all",
    1020 => "one_for_all",
    # Nexus Blitz
    1200 => "nexus_blitz",
    1300 => "nexus_blitz",
    # Ultimate Spellbook
    1400 => "ultimate_spellbook",
    # Brawl
    2300 => "brawl",
    # Co-op vs AI
    7 => "bot",
    31 => "bot",
    32 => "bot",
    33 => "bot",
    52 => "bot",
    67 => "bot",
    800 => "bot",
    810 => "bot",
    820 => "bot",
    830 => "bot",
    840 => "bot",
    850 => "bot",
    870 => "bot",
    880 => "bot",
    890 => "bot",
    # Tutorial
    2000 => "tutorial",
    2010 => "tutorial",
    2020 => "tutorial",
    # Twisted Treeline (retired map)
    8 => "twisted_treeline",
    9 => "twisted_treeline",
    41 => "twisted_treeline",
    460 => "twisted_treeline",
    470 => "twisted_treeline",
    # Dominion / Crystal Scar (retired map)
    16 => "dominion",
    17 => "dominion",
    25 => "dominion",
    96 => "ascension",
    317 => "dominion",
    910 => "ascension",
    # Limited-time / rotating game modes
    61 => "team_builder",
    72 => "snowdown",
    73 => "snowdown",
    75 => "hexakill",
    98 => "hexakill",
    91 => "doom_bots",
    92 => "doom_bots",
    93 => "doom_bots",
    300 => "poro_king",
    310 => "nemesis",
    313 => "black_market_brawlers",
    315 => "nexus_siege",
    325 => "all_random",
    600 => "blood_hunt",
    610 => "dark_star",
    920 => "poro_king",
    940 => "nexus_siege",
    950 => "doom_bots",
    960 => "doom_bots",
    980 => "star_guardian",
    990 => "star_guardian",
    1000 => "project_hunters",
    1030 => "odyssey",
    1040 => "odyssey",
    1050 => "odyssey",
    1060 => "odyssey",
    1070 => "odyssey",
    # TFT (shouldn't appear in LoL history but map defensively)
    1090 => "tft",
    1100 => "tft",
    1110 => "tft",
    1111 => "tft",
    1210 => "tft"
  }

  @labels %{
    "ranked_solo" => "Ranked Solo/Duo",
    "ranked_flex" => "Ranked Flex",
    "ranked_premade" => "Ranked Premade",
    "ranked_team" => "Ranked Team",
    "ranked_dynamic" => "Ranked Dynamic",
    "normal_draft" => "Normal Draft",
    "normal_blind" => "Normal Blind",
    "quickplay" => "Quickplay",
    "swiftplay" => "Swiftplay",
    "clash" => "Clash",
    "aram" => "ARAM",
    "aram_clash" => "ARAM Clash",
    "urf" => "URF",
    "arena" => "Arena",
    "swarm" => "Swarm",
    "one_for_all" => "One for All",
    "nexus_blitz" => "Nexus Blitz",
    "ultimate_spellbook" => "Ultimate Spellbook",
    "brawl" => "Brawl",
    "bot" => "Co-op vs AI",
    "tutorial" => "Tutorial",
    "custom" => "Custom",
    "twisted_treeline" => "Twisted Treeline",
    "dominion" => "Dominion",
    "ascension" => "Ascension",
    "hexakill" => "Hexakill",
    "doom_bots" => "Doom Bots",
    "poro_king" => "Poro King",
    "nemesis" => "Nemesis",
    "nexus_siege" => "Nexus Siege",
    "team_builder" => "Team Builder",
    "snowdown" => "Snowdown Showdown",
    "all_random" => "All Random",
    "blood_hunt" => "Blood Hunt",
    "dark_star" => "Dark Star",
    "star_guardian" => "Star Guardian",
    "project_hunters" => "PROJECT: Hunters",
    "odyssey" => "Odyssey",
    "black_market_brawlers" => "Black Market Brawlers",
    "tft" => "TFT",
    "other" => "Other"
  }

  # Ordered list of queue types to display in the UI, with their defaults.
  # {type, label, included_by_default?}
  @ui_queues [
    # Active competitive/normal modes
    {"ranked_solo", "Ranked Solo/Duo", true},
    {"ranked_flex", "Ranked Flex", false},
    {"normal_draft", "Normal Draft", false},
    {"normal_blind", "Normal Blind", false},
    {"quickplay", "Quickplay", false},
    {"swiftplay", "Swiftplay", false},
    {"clash", "Clash", false},
    # Active special modes
    {"aram", "ARAM", false},
    {"aram_clash", "ARAM Clash", false},
    {"urf", "URF", false},
    {"arena", "Arena", false},
    {"swarm", "Swarm", false},
    {"one_for_all", "One for All", false},
    {"nexus_blitz", "Nexus Blitz", false},
    {"ultimate_spellbook", "Ultimate Spellbook", false},
    {"brawl", "Brawl", false},
    # Misc
    {"bot", "Co-op vs AI", false},
    {"custom", "Custom", false},
    {"tutorial", "Tutorial", false},
    # Legacy / retired modes
    {"twisted_treeline", "Twisted Treeline", false},
    {"dominion", "Dominion", false},
    {"ascension", "Ascension", false},
    {"hexakill", "Hexakill", false},
    {"doom_bots", "Doom Bots", false},
    {"poro_king", "Poro King", false},
    {"nemesis", "Nemesis", false},
    {"nexus_siege", "Nexus Siege", false},
    {"team_builder", "Team Builder", false},
    {"snowdown", "Snowdown Showdown", false},
    {"all_random", "All Random", false},
    {"blood_hunt", "Blood Hunt", false},
    {"dark_star", "Dark Star", false},
    {"star_guardian", "Star Guardian", false},
    {"project_hunters", "PROJECT: Hunters", false},
    {"odyssey", "Odyssey", false},
    {"black_market_brawlers", "Black Market Brawlers", false},
    {"ranked_premade", "Ranked Premade", false},
    {"ranked_team", "Ranked Team", false},
    {"ranked_dynamic", "Ranked Dynamic", false},
    {"tft", "TFT", false},
    # Catch-all for any future Riot queue IDs not yet mapped
    {"other", "Other", false}
  ]

  # Queue types that have lane position data from Riot's teamPosition field
  @position_queues ~w(ranked_solo ranked_flex normal_draft normal_blind quickplay swiftplay clash)

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
