# scripts-ros :: lists/route_UP.rsc
# Installed as the script route_UP and run every 10 seconds.
#
# RouterOS disables a route whose gateway is unreachable, and the container
# gateway is unreachable every time the container restarts. Without this the
# proxy routes stay disabled after the container comes back and traffic
# silently falls through to the WAN.

:foreach c in={"MihomoProxyRoS0";"MihomoProxyRoS1"} do={
    :local r [/ip/route/find where comment=$c and disabled=yes]
    :if ([:len $r] > 0) do={
        /ip/route/set $r disabled=no
        :log info ("route_UP: re-enabled " . $c)
    }
}
