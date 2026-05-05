defmodule FrontmanServerWeb.EntraAuthController do
  use FrontmanServerWeb, :controller

  alias FrontmanServer.Accounts
  alias FrontmanServer.Accounts.User
  alias FrontmanServer.Repo
  alias FrontmanServerWeb.UserAuth
  require Logger

  @authorize_url "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
  @token_url "https://login.microsoftonline.com/common/oauth2/v2.0/token"
  @redirect_uri "https://frontman-1.glimmung.dev.romaine.life/"
  @origin "https://frontman-1.glimmung.dev.romaine.life"

  def request(conn, _params) do
    verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "client_id" => client_id!(),
        "response_type" => "code",
        "redirect_uri" => @redirect_uri,
        "response_mode" => "query",
        "scope" => "openid profile email User.Read",
        "state" => state,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    conn
    |> put_session(:entra_state, state)
    |> put_session(:entra_code_verifier, verifier)
    |> redirect(external: "#{@authorize_url}?#{query}")
  end

  def callback(conn, %{"error" => _error}) do
    conn
    |> cleanup()
    |> put_flash(:error, "Entra sign in was cancelled.")
    |> redirect(to: ~p"/users/log-in?entra_failed=1")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with ^state <- get_session(conn, :entra_state),
         verifier when is_binary(verifier) <- get_session(conn, :entra_code_verifier),
         {:ok, id_token} <- exchange_code(code, verifier),
         {:ok, claims} <- decode_claims(id_token),
         :ok <- validate_claims(claims),
         {:ok, user} <- find_or_create_user(claims) do
      conn
      |> cleanup()
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      reason ->
        Logger.warning("Entra sign in failed after callback: #{safe_failure(reason)}")

        conn
        |> cleanup()
        |> put_flash(:error, "Entra sign in failed.")
        |> redirect(to: ~p"/users/log-in?entra_failed=1")
    end
  end

  def callback(conn, _params) do
    conn
    |> cleanup()
    |> put_flash(:error, "Entra sign in failed.")
    |> redirect(to: ~p"/users/log-in?entra_failed=1")
  end

  defp exchange_code(code, verifier) do
    body =
      URI.encode_query(%{
        "client_id" => client_id!(),
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => @redirect_uri,
        "code_verifier" => verifier,
        "scope" => "openid profile email User.Read"
      })

    case Req.post(@token_url,
           body: body,
           headers: [
             {"content-type", "application/x-www-form-urlencoded"},
             {"origin", @origin}
           ]
         ) do
      {:ok, %{status: 200, body: %{"id_token" => id_token}}} ->
        {:ok, id_token}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Entra token exchange failed: #{status} #{safe_entra_error(body)}")
        {:error, :token_exchange_failed}

      {:error, reason} ->
        Logger.warning("Entra token exchange request failed: #{inspect(reason)}")
        {:error, :token_exchange_failed}
    end
  end

  defp safe_entra_error(%{"error" => error, "error_description" => description}) do
    "#{error}: #{description}"
  end

  defp safe_entra_error(%{"error" => error}), do: error
  defp safe_entra_error(_), do: "unknown_error"

  defp safe_failure({:error, %Ecto.Changeset{} = changeset}) do
    "user_insert_failed: #{inspect(changeset.errors)}"
  end

  defp safe_failure({:error, reason}), do: inspect(reason)
  defp safe_failure(nil), do: "missing_session_value"
  defp safe_failure(other) when is_binary(other), do: "unexpected_string_value"
  defp safe_failure(other), do: inspect(other)

  defp decode_claims(id_token) do
    case String.split(id_token, ".") do
      [_header, payload, _sig] ->
        payload
        |> Base.url_decode64!(padding: false)
        |> Jason.decode()

      _ ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  defp validate_claims(claims) do
    aud = claims["aud"]
    exp = claims["exp"]
    email = claims["preferred_username"] || claims["email"] || claims["upn"]

    cond do
      aud != client_id!() ->
        {:error, :bad_audience}

      not is_integer(exp) or exp <= System.system_time(:second) ->
        {:error, :expired}

      not allowed_email?(email) ->
        {:error, :email_not_allowed}

      true ->
        :ok
    end
  end

  defp find_or_create_user(claims) do
    email = String.downcase(claims["preferred_username"] || claims["email"] || claims["upn"])
    name = claims["name"] || email

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

  defp client_id! do
    System.fetch_env!("ENTRA_CLIENT_ID")
  end

  defp cleanup(conn) do
    conn
    |> delete_session(:entra_state)
    |> delete_session(:entra_code_verifier)
  end
end
