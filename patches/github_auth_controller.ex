defmodule FrontmanServerWeb.GithubAuthController do
  use FrontmanServerWeb, :controller

  alias FrontmanServer.Accounts
  alias FrontmanServer.Accounts.User
  alias FrontmanServer.Repo
  alias FrontmanServerWeb.UserAuth
  require Logger

  @authorize_url "https://github.com/login/oauth/authorize"
  @token_url "https://github.com/login/oauth/access_token"
  @user_url "https://api.github.com/user"
  @emails_url "https://api.github.com/user/emails"
  @redirect_uri "https://frontman-1.glimmung.dev.romaine.life/auth/github/callback"
  @signed_in_path "/frontman"

  def request(conn, _params) do
    state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "client_id" => client_id!(),
        "redirect_uri" => @redirect_uri,
        "scope" => "read:user user:email",
        "state" => state
      })

    conn
    |> put_session(:github_state, state)
    |> put_session(:user_return_to, @signed_in_path)
    |> redirect(external: "#{@authorize_url}?#{query}")
  end

  def callback(conn, %{"error" => _error}) do
    conn
    |> cleanup()
    |> put_flash(:error, "GitHub sign in was cancelled.")
    |> redirect(to: ~p"/users/log-in?github_failed=1")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with ^state <- get_session(conn, :github_state),
         {:ok, token} <- exchange_code(code),
         {:ok, profile} <- fetch_profile(token),
         {:ok, emails} <- fetch_emails(token),
         {:ok, email} <- allowed_verified_email(profile, emails),
         {:ok, user} <- find_or_create_user(profile, email) do
      conn
      |> cleanup()
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      reason ->
        Logger.warning("GitHub sign in failed after callback: #{safe_failure(reason)}")

        conn
        |> cleanup()
        |> put_flash(:error, "GitHub sign in failed.")
        |> redirect(to: ~p"/users/log-in?github_failed=1")
    end
  end

  def callback(conn, _params) do
    conn
    |> cleanup()
    |> put_flash(:error, "GitHub sign in failed.")
    |> redirect(to: ~p"/users/log-in?github_failed=1")
  end

  defp exchange_code(code) do
    body =
      URI.encode_query(%{
        "client_id" => client_id!(),
        "client_secret" => client_secret!(),
        "code" => code,
        "redirect_uri" => @redirect_uri
      })

    case Req.post(@token_url,
           body: body,
           headers: [
             {"accept", "application/json"},
             {"content-type", "application/x-www-form-urlencoded"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("GitHub token exchange failed: #{status} #{safe_github_error(body)}")
        {:error, :token_exchange_failed}

      {:error, reason} ->
        Logger.warning("GitHub token exchange request failed: #{inspect(reason)}")
        {:error, :token_exchange_failed}
    end
  end

  defp fetch_profile(token) do
    case Req.get(@user_url, headers: github_headers(token)) do
      {:ok, %{status: 200, body: profile}} when is_map(profile) -> {:ok, profile}
      {:ok, %{status: status, body: body}} -> {:error, {:profile_fetch_failed, status, body}}
      {:error, reason} -> {:error, {:profile_fetch_failed, reason}}
    end
  end

  defp fetch_emails(token) do
    case Req.get(@emails_url, headers: github_headers(token)) do
      {:ok, %{status: 200, body: emails}} when is_list(emails) -> {:ok, emails}
      {:ok, %{status: status, body: body}} -> {:error, {:emails_fetch_failed, status, body}}
      {:error, reason} -> {:error, {:emails_fetch_failed, reason}}
    end
  end

  defp allowed_verified_email(profile, emails) do
    verified_emails =
      emails
      |> Enum.filter(&(&1["verified"] == true))
      |> Enum.map(& &1["email"])
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)

    profile_email =
      case profile["email"] do
        email when is_binary(email) and email != "" -> [String.downcase(email)]
        _ -> []
      end

    candidate = Enum.find(verified_emails ++ profile_email, &allowed_email?/1)

    cond do
      is_binary(candidate) -> {:ok, candidate}
      verified_emails == [] and profile_email == [] -> {:error, :missing_verified_email}
      true -> {:error, :email_not_allowed}
    end
  end

  defp find_or_create_user(profile, email) do
    name = profile["name"] || profile["login"] || email

    case Accounts.get_user_by_email(email) do
      nil ->
        %User{}
        |> User.oauth_registration_changeset(%{email: email, name: name})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  defp allowed_email?(email) when is_binary(email) do
    normalized = String.downcase(email)

    allowed_emails()
    |> Enum.any?(&(&1 == normalized))
  end

  defp allowed_email?(_), do: false

  defp allowed_emails do
    "ALLOWED_EMAILS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.downcase(String.trim(&1)))
  end

  defp github_headers(token) do
    [
      {"accept", "application/vnd.github+json"},
      {"authorization", "Bearer #{token}"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "frontman-selfhost"}
    ]
  end

  defp safe_github_error(%{"error" => error, "error_description" => description}) do
    "#{error}: #{description}"
  end

  defp safe_github_error(%{"error" => error}), do: error
  defp safe_github_error(_), do: "unknown_error"

  defp safe_failure({:error, %Ecto.Changeset{} = changeset}) do
    "user_insert_failed: #{inspect(changeset.errors)}"
  end

  defp safe_failure({:error, reason}), do: inspect(reason)
  defp safe_failure(nil), do: "missing_session_value"
  defp safe_failure(other) when is_binary(other), do: "unexpected_string_value"
  defp safe_failure(other), do: inspect(other)

  defp client_id! do
    System.fetch_env!("GITHUB_CLIENT_ID")
  end

  defp client_secret! do
    System.fetch_env!("GITHUB_CLIENT_SECRET")
  end

  defp cleanup(conn) do
    delete_session(conn, :github_state)
  end
end
