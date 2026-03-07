defmodule BookmovesWeb.UserSessionHTML do
  use BookmovesWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:bookmoves, Bookmoves.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
