# scripts-ros :: modules/33-mihomo-env.rsc
# Container environment variables: the actual mihomo policy. One table, one
# loop. Existing values are never overwritten -- if a key is already present
# the operator (or a previous run) set it deliberately, and silently resetting
# someone tuned rule list would be the worst possible surprise here.
#
# To change a value after install: /container/envs/set [find where key="X" and
# list="MihomoProxyRoS"] value="..."  then restart the container.
#
# LINK1 and SUB_LINK1 are deliberately NOT here -- they are per-user secrets
# and live in modules/60-links.rsc, which can be re-run on its own.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mFetch

$mHdr "MihomoProxyRoS environment"

:local envs {
    {"k"="FAKE_IP_RANGE";     "v"="198.18.0.0/15"};
    {"k"="FAKE_IP_FILTER1";   "v"="DOMAIN,www.youtube.com,real-ip"};
    {"k"="FAKE_IP_TTL";       "v"="10"};
    {"k"="LOG_LEVEL";         "v"="error"};
    {"k"="NAMESERVER_POLICY"; "v"="tmdb-image-prod.b-cdn.net#https://dns.quad9.net/dns-query,+.themoviedb.org#https://dns.quad9.net/dns-query,+.tmdb.org#https://dns.quad9.net/dns-query,rule-set:META_geosite_meta#https://dns.quad9.net/dns-query"};
    {"k"="BYEDPI_CMD";        "v"="-Ku -a1 -An -d1 -s1+s -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -At,r,s -s1 -q1 -At,r,s -s5 -o2 -At,r,s -o1 -d1 -r1+s -s1+s -d3+s -At,r,s -f-1 -r1+s -At,r,s -s1 -o1+s -s-1"};
    {"k"="GROUP";             "v"="YouTube,Telegram,Discord,META,SuperCell,AI,Twitch"};
    {"k"="YOUTUBE_GEOSITE";   "v"="youtube"};
    {"k"="TELEGRAM_GEOSITE";  "v"="telegram"};
    {"k"="TELEGRAM_GEOIP";    "v"="telegram"};
    {"k"="TELEGRAM_AS";       "v"="AS62041,AS59930,AS62014,AS211157,AS44907"};
    {"k"="TELEGRAM_IPCIDR";   "v"="109.239.140.0/24,5.28.192.0/18,194.221.61.2/32,172.121.110.0/24,142.252.197.0/24"};
    {"k"="DISCORD_GEOSITE";   "v"="discord"};
    {"k"="DISCORD_GEOIP";     "v"="discord"};
    {"k"="META_GEOSITE";      "v"="meta"};
    {"k"="META_GEOIP";        "v"="facebook"};
    {"k"="META_AS";           "v"="AS32934,AS54115,AS63293"};
    {"k"="META_IPCIDR";       "v"="41.189.185.0/24,202.59.209.0/24,223.27.200.0/24,223.27.237.0/24"};
    {"k"="SUPERCELL_GEOSITE"; "v"="supercell"};
    {"k"="AI_GEOSITE";        "v"="category-ai-!cn,openai,google-gemini,anthropic"};
    {"k"="AI_AS";             "v"="AS399358,AS60808"};
    {"k"="AI_IPCIDR";         "v"="216.73.216.0/22"};
    {"k"="TWITCH_GEOSITE";    "v"="twitch"};
    {"k"="RULES1";            "v"="AND,((NETWORK,udp),(DST-PORT,443)),REJECT"}
}

:local added 0
:local kept 0
:onerror e in={
    :foreach en in=$envs do={
        :local k ($en->"k")
        :if ([:len [/container/envs/find where key=$k and list="MihomoProxyRoS"]] = 0) do={
            /container/envs/add key=$k list=MihomoProxyRoS value=($en->"v")
            :set added ($added + 1)
        } else={
            :set kept ($kept + 1)
        }
    }
} do={ $mErr "envs" $e }
$mOk ($added . " env(s) added, " . $kept . " kept as configured")

# The zapret engine only ships for these architectures; adding the keys on
# anything else gives the container two variables it will never read.
:local arch [/system/resource/get architecture-name]
:if ($arch = "arm64" or $arch = "x86_64") do={
    :onerror e in={
        :foreach k in={"ZAPRET_CMD";"ZAPRET2_CMD"} do={
            :if ([$mNeed id=[/container/envs/find where key=$k and list="MihomoProxyRoS"] name=("env " . $k)]) do={
                /container/envs/add key=$k list=MihomoProxyRoS value=""
                $mOk ("env " . $k)
            }
        }
    } do={ $mErr "zapret envs" $e }
} else={
    $mSay ("  [ -- ] zapret envs skipped, not supported on " . $arch)
}

# WhatsApp needs a hand-maintained rule block that changes more often than this
# repository does, so it is pulled from upstream instead of being frozen here.
:onerror e in={
    :local wa [$mFetch "https://raw.githubusercontent.com/Medium1992/mihomo-proxy-ros/refs/heads/main/custom_list/add_env_WA.rsc"]
    :if ([:len $wa] > 0) do={
        :local fn [:parse $wa]
        $fn
        $mOk "WhatsApp rules applied from upstream"
    } else={
        $mSay "  [ -- ] WhatsApp rules unavailable, skipped"
    }
} do={ $mErr "whatsapp rules" $e }
