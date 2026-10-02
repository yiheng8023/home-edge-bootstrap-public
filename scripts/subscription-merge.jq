# Only node records and node membership may come from the subscription.
def canon: gsub("[^\\p{L}\\p{N}]"; "") | ascii_downcase;
def require($condition; $message): if $condition then . else error($message) end;
($base[0]) as $b | ($subscription[0]) as $s | ($filters[0] // {}) as $f |
require(($b|type)=="object" and ($s|type)=="object"; "invalid profile mapping") |
require(($b.proxies|type)=="array" and ($s.proxies|type)=="array" and ($s.proxies|length)>0; "missing nodes") |
require((($b["proxy-providers"] // {})|length)==0; "provider-based profiles use their native updater") |
require(($s.proxies|all(.name|type=="string")) and ($s.proxies|map(.name)|unique|length)==($s.proxies|length); "duplicate node names") |
($b.proxies|map(.name)) as $oldNames |
($b.proxies|map({key:(.name|canon),value:.})|from_entries) as $oldRecords |
($b.proxies|map({key:(.name|canon),value:.name})|from_entries) as $aliases |
require(($aliases|length)==($oldNames|length); "ambiguous existing aliases") |
($s.proxies|map(
  . as $new | ($oldRecords[(.name|canon)] // {}) as $old |
  require(."skip-cert-verify"!=true or $old."skip-cert-verify"==true; "automatic certificate downgrade refused") |
  require($old.type!="http" or $old.tls!=true or $new.type!="http" or $new.tls==true; "automatic HTTP TLS downgrade refused") |
  .name=($aliases[(.name|canon)] // .name)
)) as $nodes |
($nodes|map(.name)) as $newNames |
require(($newNames|unique|length)==($newNames|length); "ambiguous new aliases") |
($b | .proxies=$nodes | .["proxy-groups"] |= map(
  . as $g | (.proxies // []) as $refs |
  if ($refs|any(. as $n | $oldNames|index($n))) then
    if ($refs|all(. as $n | $oldNames|index($n))) then
      if ($f[$g.name]|type)=="string" then
        .proxies=($newNames|map(select(test($f[$g.name]))))
      elif ($refs|sort)==($oldNames|sort) then .proxies=$newNames
      else require(($refs|all(. as $n | $newNames|index($n))); "subset needs explicit filter or missing fixed member") end
    else require(($refs|all(. as $n | if ($oldNames|index($n)) then ($newNames|index($n)) else true end)); "missing fixed policy member") end
  else . end
)) as $candidate |
($candidate["proxy-groups"]|map(.name)) as $groupNames |
require(($candidate["proxy-groups"]|all((.proxies // [])|all(. as $n | (($newNames+$groupNames+["DIRECT","REJECT","PASS"])|index($n))))); "dangling policy reference") |
require(($candidate["proxy-groups"]|all(.type!="select" or ((.proxies // [])|length)>0)); "empty selectable group") |
require(($snapshot[0].proxies | to_entries | all(
  . as $entry | if .value.type=="Selector" then
    if .key=="GLOBAL" and ($groupNames|index("GLOBAL")|not) then (($newNames+$groupNames+["DIRECT","REJECT"])|index($entry.value.now))
    else ($candidate["proxy-groups"]|map(select(.name==$entry.key))|.[0].proxies|index($entry.value.now)) end
  else true end
)); "pinned selection removed; keep current profile") |
$candidate
