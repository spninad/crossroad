defmodule Cloudmsg.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CloudmsgWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:cloudmsg, :dns_cluster_query) || :ignore},
      # Manifold PubSub system
      Cloudmsg.Router,
      # Session management
      Cloudmsg.Session.Registry,
      Cloudmsg.Session.Presence,
      # Phoenix Endpoint (must be last)
      CloudmsgWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Cloudmsg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CloudmsgWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
