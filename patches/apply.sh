#!/bin/sh
set -eu

repo="${1:-/src}"
server_dir="$repo/apps/frontman_server"
patch_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

cp "$patch_dir/github_auth_controller.ex" \
  "$server_dir/lib/frontman_server_web/controllers/github_auth_controller.ex"

cat "$patch_dir/dark-mode-overrides.css" \
  >> "$repo/libs/client/src/styles/frontman-theme.css"
cp "$patch_dir/dark-mode-overrides.css" \
  "$server_dir/priv/static/dark-mode-overrides.css"

sed -i 's|className="flex flex-col h-screen w-screen bg-background text-foreground"|className="dark flex flex-col h-screen w-screen bg-background text-foreground"|' \
  "$repo/libs/client/src/Client__App.res"
sed -i 's|${clientCssTag}|${clientCssTag}\
    <link rel="stylesheet" href="/dark-mode-overrides.css">|' \
  "$repo/libs/frontman-core/src/FrontmanCore__UIShell.res"

tmp_router="$(mktemp)"
awk '
  !done && /pipe_through\(\[:browser, :redirect_if_user_is_authenticated\]\)/ {
    sub(/pipe_through\(\[:browser, :redirect_if_user_is_authenticated\]\)/, "pipe_through([:browser, :redirect_if_user_is_authenticated])")
    print
    print "    get(\"/github\", GithubAuthController, :request)"
    print "    get(\"/github/callback\", GithubAuthController, :callback)"
    done = 1
    next
  }
  { print }
' "$server_dir/lib/frontman_server_web/router.ex" > "$tmp_router"
mv "$tmp_router" "$server_dir/lib/frontman_server_web/router.ex"

sed -i 's|discord_new_users_webhook_url: env!("DISCORD_NEW_USERS_WEBHOOK_URL", :string!)|discord_new_users_webhook_url: env!("DISCORD_NEW_USERS_WEBHOOK_URL", :string, nil)|' \
  "$server_dir/config/runtime.exs"

sed -i 's|enabled: true|enabled: env_boolean.("FRONTMAN_ENABLE_SIGNUP_WORKERS", false)|g' \
  "$server_dir/config/runtime.exs"

sed -i 's|api_key: env!("RESEND_API_KEY", :string!)|api_key: env!("RESEND_API_KEY", :string, nil)|' \
  "$server_dir/config/runtime.exs"
