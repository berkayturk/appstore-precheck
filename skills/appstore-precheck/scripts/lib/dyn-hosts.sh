#!/usr/bin/env bash
# lib/dyn-hosts.sh — which hosts the running app contacted, and whether the ones that
# belong to known ad / attribution vendors are declared in NSPrivacyTrackingDomains
# (dyn-hosts-contacted, guideline 5.1.2 parity). Pure text over captured files; the
# capture itself (log stream with SIMCTL_CHILD_CFNETWORK_DIAGNOSTICS=3, or the opt-in
# tcpdump pktap) is dynamic-run.sh's job. Sourced by dynamic-run.sh. Bash 3.2.
#
# LIMITS, stated up front:
#   * CFNetwork diagnostics see URLSession / NSURLConnection traffic. Flutter's Dart
#     HttpClient and some Go / Rust networking stacks bypass CFNetwork entirely, so
#     the log-based capture MISSES them; the runner records that as a SKIP reason
#     unless --pktap was given (sudo tcpdump on the pktap interface sees DNS for
#     every process). Default off: it needs sudo.
#   * The vendor→domain catalogue below mirrors the §16 tracking-SDK list in scan.sh
#     and goes stale the same way (MAINTENANCE.md, quarterly). A host that matches
#     no vendor is reported, not judged.

# dyn_hosts_from_log <log-file> -> unique lower-cased hostnames, one per line.
# Reads URL hosts ("request https://host/…") and "connected to host:port" lines.
dyn_hosts_from_log() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  {
    grep -oE 'https?://[A-Za-z0-9._-]+' "$f" 2>/dev/null | sed -E 's#https?://##'
    grep -oE 'connected to [A-Za-z0-9._-]+' "$f" 2>/dev/null | sed -E 's/connected to //'
  } | tr 'A-Z' 'a-z' | grep -E '^[a-z0-9._-]+$' | grep -E '\.' | sort -u   # a host has a dot (or is an IPv4 literal)
}

# dyn_hosts_from_tcpdump_text <text-file> -> hostnames from DNS queries ("A? host.").
dyn_hosts_from_tcpdump_text() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  grep -oE ' (A|AAAA|HTTPS)\? [A-Za-z0-9._-]+\.' "$f" 2>/dev/null \
    | sed -E 's/^ (A|AAAA|HTTPS)\? //; s/\.$//' | tr 'A-Z' 'a-z' | sort -u
}

# dyn_tracking_domain_catalogue -> "<vendor><TAB><domain-suffix>" lines. Suffix
# match: a contacted host equals the suffix or ends in ".<suffix>".
dyn_tracking_domain_catalogue() {
  cat <<'EOF'
AppsFlyer	appsflyer.com
AppsFlyer	appsflyersdk.com
Adjust	adjust.com
Adjust	adj.st
Branch	branch.io
Branch	app.link
Google Ads	doubleclick.net
Google Ads	googleadservices.com
Google Ads	googlesyndication.com
Google Ads	admob.com
Meta Audience Network / FB SDK	graph.facebook.com
AppLovin	applovin.com
AppLovin	applvn.com
ironSource	ironsrc.com
ironSource	ironsource.com
Unity Ads	unityads.unity3d.com
Vungle	vungle.com
Chartboost	chartboost.com
InMobi	inmobi.com
Mintegral	mintegral.com
Pangle	pangle.io
Pangle	pangleglobal.com
Singular	singular.net
Kochava	kochava.com
Tenjin	tenjin.io
Tenjin	tenjin.com
EOF
}

# _dyn_host_matches <host> <suffix> -> 0 when host == suffix or host ends in .suffix
_dyn_host_matches() { [[ "$1" == "$2" || "$1" == *".$2" ]]; }

# dyn_declared_tracking_domains <PrivacyInfo.xcprivacy|""> -> declared domains, one per line.
dyn_declared_tracking_domains() {
  local f="${1:-}"
  [[ -n "$f" && -f "$f" ]] || return 0
  if command -v plutil >/dev/null 2>&1 && plutil -extract NSPrivacyTrackingDomains json -o - "$f" >/dev/null 2>&1; then
    plutil -extract NSPrivacyTrackingDomains json -o - "$f" 2>/dev/null | jq -r '.[]?' 2>/dev/null
  else
    awk '/<key>NSPrivacyTrackingDomains<\/key>/ {on=1; next} on && /<\/array>/ {exit} on && /<string>/ { sub(/.*<string>/,""); sub(/<\/string>.*/,""); print }' "$f"
  fi | tr 'A-Z' 'a-z'
}

# dyn_hosts_parity <hosts-file> <PrivacyInfo.xcprivacy|""> -> JSON
#   {contacted:[…], tracking:[{host,vendor,declared}], declared:[…], undeclared:[…]}
dyn_hosts_parity() {
  local hosts="$1" privacy="${2:-}" host vendor suffix declared d hit tmp
  tmp="$(mktemp)"
  dyn_declared_tracking_domains "$privacy" > "$tmp.decl"
  : > "$tmp.track"
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    while IFS="$(printf '\t')" read -r vendor suffix; do
      [[ -n "$suffix" ]] || continue
      _dyn_host_matches "$host" "$suffix" || continue
      declared=false
      while IFS= read -r d; do [[ -n "$d" ]] && _dyn_host_matches "$host" "$d" && declared=true; done < "$tmp.decl"
      printf '%s\t%s\t%s\n' "$host" "$vendor" "$declared" >> "$tmp.track"
      break
    done < <(dyn_tracking_domain_catalogue)
  done < "$hosts"
  jq -n -c --rawfile hosts "$hosts" --rawfile decl "$tmp.decl" --rawfile track "$tmp.track" '
    ($hosts | split("\n") | map(select(. != ""))) as $c
    | ($decl  | split("\n") | map(select(. != ""))) as $d
    | ($track | split("\n") | map(select(. != "")) | map(split("\t") | {host:.[0], vendor:.[1], declared:(.[2]=="true")})) as $t
    | {contacted:$c, declared:$d, tracking:$t, undeclared:[$t[] | select(.declared|not) | .host]}'
  hit=$?
  rm -f "$tmp" "$tmp.decl" "$tmp.track"
  return $hit
}

# dyn_hosts_line <parity-json> <source-note> -> one transcript line for dyn-hosts-contacted.
dyn_hosts_line() {
  local rep="$1" note="${2:-}" n u t
  n="$(jq -r '.contacted|length' <<<"$rep")"; t="$(jq -r '.tracking|length' <<<"$rep")"; u="$(jq -r '.undeclared|length' <<<"$rep")"
  if (( n == 0 )); then
    printf 'DYNAMIC-SKIP: 5.1.2 [dyn-hosts-contacted] — no host observed in the capture window%s\n' "${note:+ ($note)}"
    return 0
  fi
  if (( u > 0 )); then
    printf 'DYNAMIC-FINDING: 5.1.2 [dyn-hosts-contacted] — %s host(s) contacted; %s belong to known ad/attribution vendors and %s of those are NOT in NSPrivacyTrackingDomains: %s%s\n' \
      "$n" "$t" "$u" "$(jq -r '[.tracking[] | select(.declared|not) | "\(.host) (\(.vendor))"] | join(", ")' <<<"$rep")" "${note:+ ($note)}"
    return 0
  fi
  if (( t > 0 )); then
    printf 'DYNAMIC-PASS: 5.1.2 [dyn-hosts-contacted] — %s host(s) contacted; %s known ad/attribution host(s), all declared in NSPrivacyTrackingDomains%s\n' "$n" "$t" "${note:+ ($note)}"
    return 0
  fi
  printf 'DYNAMIC-PASS: 5.1.2 [dyn-hosts-contacted] — %s host(s) contacted, none matches a known ad/attribution vendor: %s%s\n' \
    "$n" "$(jq -r '.contacted | .[0:6] | join(", ")' <<<"$rep")" "${note:+ ($note)}"
}
