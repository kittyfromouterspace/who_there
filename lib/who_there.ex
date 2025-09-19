defmodule WhoThere do
  @moduledoc """
  WhoThere is a privacy-first analytics library for Phoenix applications.

  It provides comprehensive analytics tracking with features like:
  - Invisible request tracking
  - Bot detection and classification
  - Geographic data extraction
  - Session management
  - Multi-tenant support
  - GDPR compliance tools

  ## Quick Start

  Add WhoThere to your Phoenix application by running:

      mix igniter.install who_there

  This will automatically configure your application with sensible defaults.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhoThere.Repo
    ]

    opts = [strategy: :one_for_one, name: WhoThere.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Returns the configured WhoThere domain.
  """
  def domain, do: WhoThere.Domain

  @doc """
  Returns the configured WhoThere repo.
  """
  def repo, do: WhoThere.Repo
end
