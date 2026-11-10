#!/usr/bin/env bash
# Builds the web app for this computer against dev, signed in by itself as
# the QA user from app/.env.qa (git ignored). Open http://localhost:8099
# after starting the server. Never upload this build anywhere: it carries
# the QA password. The app only uses it on localhost.
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env.qa; set +a
FLUTTER="${FLUTTER:-/c/src/flutter/bin/flutter.bat}"
"$FLUTTER" build web --release \
  --dart-define=SUPABASE_URL=https://jepcsftdjejjzhfjnavy.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_oTLjMBC0q95QkO2UrJEaSg_-IkMyi0C \
  --dart-define=DEV_AUTO_EMAIL="$QA_EMAIL" \
  --dart-define=DEV_AUTO_PASSWORD="$QA_PASSWORD" < /dev/null
