# scripts-ros :: lists/FWD_update_list.rsc
# YOUR list. Installed once as the script FWD_update_list and never touched by
# the installer again -- add or remove names here freely, updates to the engine
# will not fight you.
#
# Each name is a .rsc fragment under the base URL. Every domain in it becomes a
# /ip dns static FWD entry pointing at $ForwardTo.

:global AddressList ""
:global ForwardTo "MihomoProxyRoS"

:global rosSets {
    {"base"="https://raw.githubusercontent.com/Medium1992/MikroTik_DNS_FWD/refs/heads/main/for_scripts";
     "items"={
        "youtube";"meta";"netflix";"discord";"rutracker";"torrent";"adguard";
        "anime";"deepl";"category-ai-!cn";"category-anticensorship";"openai";
        "google-gemini";"canva";"art";"tidal";"tiktok";"music";"tmdb";"x";
        "kinopub";"xhamster";"porn";"video";"anthropic";"xai";"notion";
        "twitch";"supercell";"xbox";"pornhub"
     }};
    {"base"="https://raw.githubusercontent.com/Medium1992/mihomo-proxy-ros/refs/heads/main/custom_list";
     "items"={"domain_custom"}}
}
