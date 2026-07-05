#!/usr/bin/env bash
# DNS and name resolution demonstration.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
DIG="$COMPOSE exec -T dns-tools dig"

echo "${BOLD}DNS & name resolution${RESET}"
note "Assumes 'make dns' is running (dns-root, dns-auth, dns-resolver, dns-tools)."
note "Servers: root=172.30.53.2  auth=172.30.53.3  resolver=172.30.53.4"
note "Learning loop: predict the answer, run the query, explain what the output proves."

step "The hierarchy: the ROOT only refers, it does not answer" \
     "no ANSWER address — an AUTHORITY NS record points at the authoritative server"
note "The root zone holds nothing but a delegation of shop.internal. Ask it for a"
note "name in that zone and it hands back a referral: 'ask ns1.shop.internal.'"
predict "Will the root server return an IP address for www.shop.internal?" \
     "No. It should return a referral to ns1.shop.internal plus a glue A record."
run "$DIG +noall +authority +additional @dns-root www.shop.internal A"
checkpoint "Which two lines prove this is a referral instead of the final answer?" \
        "The NS record delegates shop.internal, and the glue A record gives ns1.shop.internal an address."
pause

step "The AUTHORITATIVE server gives the real answer" \
     "the 'aa' flag is set and the A records are returned"
predict "What should change when the same name is queried against dns-auth?" \
     "The answer should contain A records and the aa flag should be present."
run "$DIG +noall +answer +comments @dns-auth www.shop.internal A | grep -E 'flags|IN[[:space:]]+A'"
checkpoint "What does the aa flag tell you about dns-auth?" \
        "It is authoritative for this zone, so it owns and serves the real record data."
pause

step "One name, two A records = DNS-level load balancing" \
     "both IPs are returned; their order may rotate across queries"
note "DNS itself can spread clients across backends just by rotating the answers."
predict "How many IPv4 addresses should www.shop.internal return?" \
     "Two: 10.0.0.11 and 10.0.0.12. The order may change across repeated queries."
run "for i in 1 2 3 4; do $DIG +short @dns-auth www.shop.internal A | tr '\n' ' '; echo; done"
checkpoint "Why is this weaker than a real L4/L7 load balancer?" \
        "DNS returns addresses, but it does not inspect requests, track backend health, or guarantee an even split."
pause

step "Walk the common record TYPES — each answers a different question" ""
predict "Before each query, say what question the record type is supposed to answer." \
     "A/AAAA locate hosts, CNAME aliases names, MX routes mail, TXT stores metadata, SRV locates services, NS/SOA describe authority."
note "AAAA — the IPv6 address:"
run "$DIG +noall +answer @dns-auth www.shop.internal AAAA"
note "CNAME — an alias; note the resolver also chases it to www's A records:"
run "$DIG +noall +answer @dns-auth api.shop.internal"
checkpoint "Why does the CNAME answer include www's A records too?" \
        "The alias points at www.shop.internal, and the server includes the target records needed to finish the lookup."
note "MX — where mail for the domain goes (with priority):"
run "$DIG +noall +answer @dns-auth shop.internal MX"
note "TXT — arbitrary text (SPF / verification):"
run "$DIG +noall +answer @dns-auth shop.internal TXT"
note "SRV — locate a service: priority weight port target:"
run "$DIG +noall +answer @dns-auth _http._tcp.shop.internal SRV"
note "NS / SOA — who is authoritative, and the zone's timers:"
run "$DIG +noall +answer @dns-auth shop.internal NS"
run "$DIG +noall +answer @dns-auth shop.internal SOA"
try_it "Query cdn.shop.internal and identify whether it is a real address or an alias." \
       "$DIG +noall +answer @dns-auth cdn.shop.internal"
pause

step "Recursion: ask the RESOLVER once, it does the work" \
     "a final answer comes straight back — no referral for the client to chase"
note "A real resolver walks root -> authoritative for you; here it forwards, but the"
note "client experience is the same: one question, one final answer."
predict "Will the client see the referral chain when asking dns-resolver?" \
     "No. The resolver returns the final answer to the client."
run "$DIG +noall +answer @dns-resolver www.shop.internal A"
checkpoint "Why do clients usually ask a resolver instead of walking the hierarchy themselves?" \
        "The resolver hides the lookup work, caches answers, and gives clients one simple interface."
pause

step "Caching & TTL: the resolver remembers" \
     "the TTL is LOWER on the second query — proof it was served from cache"
note "First lookup (fetched fresh from the authoritative server, full TTL=30):"
predict "What TTL do you expect on the first resolver answer?" \
     "About 30 seconds, because the authoritative zone sets this record's TTL to 30."
run "$DIG +noall +answer @dns-resolver mail.shop.internal A"
note "…wait a few seconds, then ask again (served from cache, TTL counted down):"
run "sleep 3"
run "$DIG +noall +answer @dns-resolver mail.shop.internal A"
note "The countdown is DNS trading freshness for speed. This short pause proves"
note "the cached answer is aging; a full record change would keep serving the old"
note "answer until the remaining TTL expires."
checkpoint "If mail.shop.internal changed right after the first query, why might clients still see the old address?" \
        "Resolvers may keep serving the cached answer until its TTL expires."
pause

step "Missing names fail before the application is contacted" \
     "NXDOMAIN means the DNS name does not exist in this zone"
predict "What should happen if missing.shop.internal is not in the zone file?" \
     "The DNS response should say NXDOMAIN, and no application connection can be attempted by name."
run "$DIG +noall +comments @dns-auth missing.shop.internal A | grep -E 'status:|ANSWER:'"
checkpoint "Is NXDOMAIN an application error or a DNS resolution error?" \
        "It is a DNS resolution error: the requested name does not exist."
pause

step "Mini challenge: change one DNS fact and predict the effect" \
     "small edits make the caching and record-type rules concrete"
try_it "Open infra/dns/db.shop.internal, add 'api2 IN A 10.0.0.30', then restart dns-auth and query it." \
       "docker compose restart dns-auth && $DIG +noall +answer @dns-auth api2.shop.internal A"
note "Expected answer after the edit: api2.shop.internal. 30 IN A 10.0.0.30"
try_it "Change the TTL from 30 to 10, restart dns-auth and dns-resolver, then run the mail TTL query twice." \
       "docker compose restart dns-auth dns-resolver"
checkpoint "What should a shorter TTL improve, and what cost does it introduce?" \
        "It improves freshness after changes, but it increases resolver traffic to the authoritative server."

echo
note "${BOLD}Done.${RESET} Cleanup: docker compose --profile dns down"
