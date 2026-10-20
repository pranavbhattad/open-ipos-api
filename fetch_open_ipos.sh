#!/usr/bin/env bash
# Fetch open equity IPOs (mainboard + SME) that close for application TODAY.
# Free plan only allows the status, limit and page parameters, so we fetch ALL
# open IPOs (limit=1 per request, 6 requests/minute) and filter locally.
# Requires: curl, jq
#
# Usage:
#   1. Put your real API key on the IPOALERTS_API_KEY line below
#   2. bash fetch_open_ipos.sh
#
# Output: open_ipos.json (name, symbol, type of mainboard/SME IPOs ending today;
#         the API's "EQ" type is shown as "mainboard")

set -euo pipefail

IPOALERTS_API_KEY="${IPOALERTS_API_KEY:?Missing IPOALERTS_API_KEY secret}"


BASE="https://api.ipoalerts.in/ipos"
OUT="open_ipos.json"
ALL="all_open_ipos.tmp.json"
QUERY="status=open&limit=1"
tmp=$(mktemp)
page=1
total_pages=1

# Today's date in India time (IPO dates follow IST)
today=$(TZ=Asia/Kolkata date +%F)
echo "Today (IST): $today" >&2

echo "[]" > "$ALL"

while [ "$page" -le "$total_pages" ]; do
  resp=$(curl -s -w "\n%{http_code}" \
    -H "x-api-key: $IPOALERTS_API_KEY" \
    "$BASE?$QUERY&page=$page")
  code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')

  if [ "$code" = "429" ]; then
    wait=$(echo "$body" | jq -r '.meta.expiresIn // 10')
    echo "Rate limited. Waiting $((wait + 1))s..." >&2
    sleep "$((wait + 1))"
    continue
  elif [ "$code" != "200" ]; then
    echo "Request failed with HTTP $code: $body" >&2
    exit 1
  fi

  total_pages=$(echo "$body" | jq '.meta.totalPages')
  echo "$body" | jq '.ipos' > "$tmp"
  jq -s 'add' "$ALL" "$tmp" > "$ALL.new" && mv "$ALL.new" "$ALL"
  echo "Fetched page $page of $total_pages" >&2

  page=$((page + 1))
  if [ "$page" -le "$total_pages" ]; then
    sleep 11
  fi
done

# Keep only EQ/SME IPOs whose end date is today, and only name, symbol, type
jq --arg d "$today" '[
  .[]
  | select((.type == "EQ" or .type == "SME") and .endDate == $d)
  | {name, symbol, type: (if .type == "EQ" then "mainboard" else .type end)}
]' "$ALL" > "$OUT"

echo "Fetched $(jq 'length' "$ALL") open IPO(s) in total." >&2
rm -f "$tmp" "$ALL"
echo "Done. $(jq 'length' "$OUT") EQ/SME IPO(s) closing today saved to $OUT" >&2
