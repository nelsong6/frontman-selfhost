#!/bin/sh
set -eu

repo="${1:-/src}"
server_dir="$repo/apps/frontman_server"

perl -0pi -e 's|discord_new_users_webhook_url: env!\("DISCORD_NEW_USERS_WEBHOOK_URL", :string!\)|discord_new_users_webhook_url: env!("DISCORD_NEW_USERS_WEBHOOK_URL", :string, nil)|' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|enabled: true|enabled: env_boolean.("FRONTMAN_ENABLE_SIGNUP_WORKERS", false)|g' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|api_key: env!\("RESEND_API_KEY", :string!\)|api_key: env!("RESEND_API_KEY", :string, nil)|' \
  "$server_dir/config/runtime.exs"
