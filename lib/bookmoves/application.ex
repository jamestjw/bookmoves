defmodule Bookmoves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BookmovesWeb.Telemetry,
      Bookmoves.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:bookmoves, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:bookmoves, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bookmoves.PubSub},
      {Task, fn -> seed_positions() end},
      # Start a worker by calling: Bookmoves.Worker.start_link(arg)
      # {Bookmoves.Worker, arg},
      # Start to serve requests, typically the last entry
      BookmovesWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bookmoves.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BookmovesWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp seed_positions do
    Bookmoves.Repertoire.seed_root_positions()
  end
end
