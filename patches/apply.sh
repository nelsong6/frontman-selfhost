#!/bin/sh
set -eu

repo="${1:-/src}"
server_dir="$repo/apps/frontman_server"

cp /patches/github_auth_controller.ex \
  "$server_dir/lib/frontman_server_web/controllers/github_auth_controller.ex"

perl -0pi -e 's|get\("/", PageController, :home\)|get("/", PageController, :home)\n    get("/auth/github", GithubAuthController, :request)\n    get("/auth/github/callback", GithubAuthController, :callback)|' \
  "$server_dir/lib/frontman_server_web/router.ex"

perl -0pi -e 's|redirect\(conn, external: "https://frontman.sh"\)|redirect(conn, to: "/frontman")|' \
  "$server_dir/lib/frontman_server_web/controllers/page_controller.ex"

perl -0pi -e 's|defp signed_in_path\(_conn\), do: ~p"/"|defp signed_in_path(_conn), do: "/frontman"|' \
  "$server_dir/lib/frontman_server_web/user_auth.ex"

perl -0pi -e 's|    render\(conn, :new, form: form\)|    if System.get_env("GITHUB_CLIENT_ID") && params["github_failed"] != "1" do\n      redirect(conn, to: ~p"/auth/github")\n    else\n      render(conn, :new, form: form)\n    end|' \
  "$server_dir/lib/frontman_server_web/controllers/user_session_controller.ex"

perl -0pi -e 's|discord_new_users_webhook_url: env!\("DISCORD_NEW_USERS_WEBHOOK_URL", :string!\)|discord_new_users_webhook_url: env!("DISCORD_NEW_USERS_WEBHOOK_URL", :string, nil)|' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|enabled: true|enabled: env_boolean.("FRONTMAN_ENABLE_SIGNUP_WORKERS", false)|g' \
  "$server_dir/config/runtime.exs"

perl -0pi -e 's|api_key: env!\("RESEND_API_KEY", :string!\)|api_key: env!("RESEND_API_KEY", :string, nil)|' \
  "$server_dir/config/runtime.exs"
