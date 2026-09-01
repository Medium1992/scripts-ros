# scripts-ros :: lists/IP_MihomoProxyRoS_list.rsc
# YOUR list. Networks that must be routed through the proxy by address rather
# than by domain -- apps that never resolve a hostname, or that pin IPs.
# Everything here lands in the firewall address-list named by $AddressList,
# which the MarkConnAddressList mangle rule matches on.

:global AddressList "MihomoProxyRoS"
:global ForwardTo ""

:global rosSets {
    {"base"="https://raw.githubusercontent.com/Medium1992/MikroTik_IPlist/refs/heads/main/for_scripts";
     "items"={
        "geoipv4/telegram";
        "asnv4/AS62041";"asnv4/AS59930";"asnv4/AS62014";"asnv4/AS211157";"asnv4/AS44907";
        "geoipv4/twitter";
        "asnv4/AS13414";"asnv4/AS63179";"asnv4/AS35995";
        "geoipv4/facebook";
        "asnv4/AS32934";"asnv4/AS54115";"asnv4/AS63293";"asnv4/AS45796";
        "geoipv4/netflix";
        "asnv4/AS2906";
        "asnv4/AS399358";"asnv4/AS60808"
     }};
    {"base"="https://raw.githubusercontent.com/Medium1992/mihomo-proxy-ros/refs/heads/main/custom_list";
     "items"={"ipcidr_address_list_custom"}}
}
