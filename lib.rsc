# scripts-ros :: lib.rsc
# Shared runtime for every module. Loaded first by install.rsc, always.
#
# Everything here lands in /system/script/environment as a global. Modules are
# fetched and executed through [:parse], which gives each of them its OWN scope
# -- a module cannot see the caller's :local. Globals are the only channel
# between install.rsc and the modules, hence the "m" prefix on every name and
# the single environment cleanup at the very end of install.rsc (never here,
# never in a module).
#
# Output is ASCII only. RouterOS itself does not handle multi-byte charsets in
# the console, so no localisation happens at runtime -- see docs/language.md.

# ---------------------------------------------------------------- settings
# Overridable before load: point mBase at a local HTTP server to test without
# pushing to GitHub, e.g. :global mBase "http://192.168.88.10:8000"
:global mBase
:if ([:typeof $mBase] = "nothing") do={
    :global mBranch
    :if ([:typeof $mBranch] = "nothing") do={ :set mBranch "main" }
    :set mBase ("https://raw.githubusercontent.com/Medium1992/scripts-ros/refs/heads/" . $mBranch)
}

# Tag written into the comment of every object we create, so uninstall and the
# status checks can find our work without a hardcoded inventory.
:global mTag "sros"

# ------------------------------------------------------------------ output
# Fixed-width markers keep the status table aligned. Do not widen them.
#   [ ok ] present and healthy     [ -- ] absent
#   [ ++ ] created just now        [ == ] already there, skipped
#   [ !! ] error                   [ upd ] update available

:global mSay do={
    :put $1
}

:global mLog do={
    :put $1
    :log warning ("sros: " . $1)
}

:global mHdr do={
    :put ""
    :put ("== " . $1)
}

:global mOk   do={ :put ("  [ ++ ] " . $1) }
:global mSkip do={ :put ("  [ == ] " . $1) }
:global mMiss do={ :put ("  [ -- ] " . $1) }

:global mErr do={
    :put ("  [ !! ] " . $1 . ": " . $2)
    :log error ("sros: " . $1 . ": " . $2)
}

# ------------------------------------------------------------ idempotency
# Usage, and the reason there is no $mEnsure taking a command string: keeping
# the command as literal code means no escaping, no [:parse], and a real syntax
# error at load time instead of a runtime surprise.
#
#   :if ([$mNeed id=[/ip/dns/forwarders/find where name="Google"] name="dns:Google"]) do={
#       /ip/dns/forwarders/add name=Google doh-servers=https://8.8.8.8/dns-query
#       $mOk "dns:Google"
#   }

:global mNeed do={
    :global mSkip
    :local n 0
    :if ([:typeof $id] != "nothing") do={ :set n [:len $id] }
    :if ($n > 0) do={
        $mSkip $name
        :return false
    }
    :return true
}

# ------------------------------------------------------------------- input
# /terminal ask only works from an interactive terminal. Any module that calls
# these must declare itself interactive so the scheduler never runs it.

:global mAsk do={
    :local a [/terminal ask]
    :if ([:len $a] = 0) do={ :return $default }
    :return $a
}

:global mYesNo do={
    :while (true) do={
        :put ($prompt . " [y/n]")
        :local a [/terminal ask]
        :if ($a = "y" or $a = "yes") do={ :return true }
        :if ($a = "n" or $a = "no")  do={ :return false }
        :put "  please answer y or n"
    }
}

# ---------------------------------------------------------------- containers
# RouterOS 7.24.1 exposes no "status" property on a container: the state is
# only readable as the running / stopped flags, and "running" comes back as an
# empty string rather than false. One helper so no module has to remember that.
:global mContState do={
    :if ([:len [/container/find where comment=$1 and running]] > 0) do={ :return "running" }
    :if ([:len [/container/find where comment=$1 and stopped]] > 0) do={ :return "stopped" }
    :if ([:len [/container/find where comment=$1]] > 0) do={ :return "busy" }
    :return "absent"
}

# ------------------------------------------------------------------ hashing
# Verified on 7.24.1: [:convert <s> transform=md5 to=hex] returns the correct
# lowercase hex digest and handles multi-KB strings. Without to=hex the same
# call returns raw bytes, so the to= is not optional.
:global mHash do={
    :return [:convert $1 transform=md5 to=hex]
}

# ------------------------------------------------------------------ network
# Fetch a resource. Relative names resolve against $mBase, absolute URLs pass
# through. Returns "" on failure -- callers must check, never assume.
:global mFetch do={
    :global mBase
    :local url $1
    :if ([:pick $url 0 4] != "http") do={ :set url ($mBase . "/" . $url) }
    # mode must match the scheme: a plain-http dev server fetched with
    # mode=https fails, which is exactly how local testing gets set up.
    :local scheme "https"
    :if ([:pick $url 0 5] = "http:") do={ :set scheme "http" }
    :local out ""
    :onerror e in={
        :retry command={
            :local r [/tool fetch url=$url mode=$scheme output=user as-value]
            :if (($r->"status") != "finished") do={ :error "status not finished" }
            :set out ($r->"data")
        } delay=3 max=3
    } do={
        :put ("  [ !! ] fetch " . $url . ": " . $e)
        :set out ""
    }
    :return $out
}

# Fetch and execute a module. Returns false if anything went wrong, so the menu
# can report a failed step instead of silently continuing.
:global mRun do={
    :global mFetch
    :local body [$mFetch $1]
    :if ([:len $body] = 0) do={
        :put ("  [ !! ] module " . $1 . ": empty or unreachable")
        :return false
    }
    :local fn
    :onerror e in={ :set fn [:parse $body] } do={
        :put ("  [ !! ] module " . $1 . ": parse error: " . $e)
        :return false
    }
    :onerror e in={ $fn } do={
        :put ("  [ !! ] module " . $1 . ": runtime error: " . $e)
        :return false
    }
    :return true
}

# -------------------------------------------------------------------- state
# Installed versions and content hashes of the list scripts. Held in memory as
# the array $mS and persisted as a script named sros_state whose whole source
# is one ":global mS {...}" line -- loading it is a plain [:parse], and saving
# it is a full rewrite, which is much less code than patching one line inside
# a stored string.

:global mS
:if ([:typeof $mS] = "nothing") do={ :set mS [:toarray ""] }

:global mStateLoad do={
    :global mS
    :if ([:len [/system/script/find where name="sros_state"]] = 0) do={ :return true }
    :onerror e in={
        :local fn [:parse [/system/script/get [find where name="sros_state"] source]]
        $fn
    } do={
        :put ("  [ !! ] state load failed, starting empty: " . $e)
        :set mS [:toarray ""]
    }
    :return true
}

:global mStateSave do={
    :global mS
    :local body ":global mS {"
    :foreach k,v in=$mS do={
        :set body ($body . "\"" . $k . "\"=\"" . $v . "\";")
    }
    :set body ($body . "}")
    :if ([:len [/system/script/find where name="sros_state"]] = 0) do={
        /system/script/add name="sros_state" source=$body comment="sros:state"
    } else={
        /system/script/set [find where name="sros_state"] source=$body
    }
    :return true
}

:global mStateSet do={
    :global mS
    :global mStateSave
    :set ($mS->$key) $value
    $mStateSave
    :return true
}

:global mStateGet do={
    :global mS
    :local v ($mS->$1)
    :if ([:typeof $v] = "nothing") do={ :return "" }
    :return $v
}
