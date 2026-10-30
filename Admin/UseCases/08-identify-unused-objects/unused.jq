# The rules of this use case, as one jq program: which objects nothing points to.
# Inputs (--slurpfile, each an array in a one element array): $accounts $apps $certs $sites $profiles $subs $routes, and --argjson $found {"<route id>": true} for the routes the server log names.
# Output: one TSV line for each object: U (unused) or K (kept), the type, the name, why.

# What points to what
[ $subs[0][] | (.transferConfigurations // [])[] | (.site // empty) ] as $cfgSites
| [ $routes[0][] | (.steps // [])[] | select((.transferSiteExpression // "") != "") | .transferSiteExpression | split("#!#CVD#!#")[] | select(length > 0) ] as $stepSites
| ($cfgSites + $stepSites) as $siteRefs
| [ $subs[0][] | .account as $acc | (.transferConfigurations // [])[] | select((.transferProfile // "") != "") | "\($acc)\t\(.transferProfile)" ] as $profileRefs
| [ $subs[0][] | (.application // empty) ] as $appRefs
| [ $sites[0][] | (.clientCertificate, .loginCertificate, .partnerCertificate) | select(. != null and . != "") ] as $certRefs
| [ $routes[0][] | select(.type == "COMPOSITE") | (.routeTemplate // empty) ] as $templateRefs
| [ $routes[0][] | select(.type == "COMPOSITE") | (.subscriptions // [])[] ] as $subsWithRoute
| [ $routes[0][] | (.steps // [])[] | select(.type == "ExecuteRoute") | {r: .executeRoute, s: .status} ] as $exec
| [ $exec[] | select(.s == "ENABLED") | .r ] as $runOn
| [ $exec[] | select(.s != "ENABLED") | .r ] as $runOff
| [ ($sites[0][].account), ($profiles[0][].account), ($subs[0][].account), ($routes[0][] | select(.type == "COMPOSITE") | .account) | select(. != null) ] as $accountRefs

# What nothing points to
| (
    [ $accounts[0][] | select(.name as $n | $accountRefs | index($n) | not)
      | ["U", "Account", .name, "no site, transfer profile, subscription or composite route"] ]
  + [ $apps[0][] | select((.type == "AdvancedRouting" or .type == "Basic") and (.name as $n | $appRefs | index($n) | not))
      | ["U", "Application", .name, "no subscription uses it"] ]
  + [ $certs[0][] | select(.account != null and .account != "" and (.usage == "private" or .usage == "local") and (.id as $i | $certRefs | index($i) | not))
      | ["U", "Certificate", (.name // .id), "owned by \(.account), and no site names it"] ]
  + [ $routes[0][] | select(.type == "TEMPLATE" and (.id as $i | $templateRefs | index($i) | not))
      | ["U", "Route template", .name, "no composite route is made from it"] ]
  + [ $routes[0][] | select(.type == "COMPOSITE" and ((.subscriptions // []) | length) == 0)
      | ["U", "Composite route", .name, "no subscription starts it"] ]
  + [ $routes[0][] | select(.type == "SIMPLE") | . as $r
      | if ($runOn | index($r.id)) then empty
        elif ($runOff | index($r.id)) then
          (if $found[$r.id] then ["K", "Route", $r.name, "disabled now, but the server log names it: it ran in the past"]
           else ["U", "Route", $r.name, "disabled in every step that runs it, and the server log does not name it"] end)
        else ["U", "Route", $r.name, "no step of any route runs it"] end ]
  + [ $sites[0][] | select(.protocol != "as2" and .protocol != "pesit" and (.name as $n | $siteRefs | index($n) | not))
      | ["U", "Site", .name, "no subscription configuration and no route step names it"] ]
  + [ $subs[0][] | select(((.transferConfigurations // []) | length) == 0 and (.id as $i | $subsWithRoute | index($i) | not))
      | ["U", "Subscription", "\(.account) \(.folder)", "no transfer configuration and no route"] ]
  + [ $profiles[0][] | select(.default != true and ("\(.account)\t\(.name)" as $k | $profileRefs | index($k) | not))
      | ["U", "Transfer profile", .name, "owned by \(.account), and no subscription configuration names it"] ]
) | .[] | @tsv
