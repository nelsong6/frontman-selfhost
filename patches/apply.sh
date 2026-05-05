#!/bin/sh
set -eu

repo="${1:-/src}"
server_dir="$repo/apps/frontman_server"

cp /patches/github_auth_controller.ex \
  "$server_dir/lib/frontman_server_web/controllers/github_auth_controller.ex"

perl -0pi -e 's|    pipe_through\(\[:browser, :redirect_if_user_is_authenticated\]\)|    pipe_through([:browser, :redirect_if_user_is_authenticated])\n\n    get("/github", GithubAuthController, :request)\n    get("/github/callback", GithubAuthController, :callback)|' \
  "$server_dir/lib/frontman_server_web/router.ex"

perl -0pi -e 's|discord_new_users_webhook_url: env!\("DISCORD_NEW_USERS_WEBHOOK_URL", :string!\)|discord_new_users_webhook_url: env!("DISCORD_NEW_USERS_WEBHOOK_URL", :string, nil)|' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|enabled: true|enabled: env_boolean.("FRONTMAN_ENABLE_SIGNUP_WORKERS", false)|g' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|api_key: env!\("RESEND_API_KEY", :string!\)|api_key: env!("RESEND_API_KEY", :string, nil)|' \
  "$server_dir/config/runtime.exs"
