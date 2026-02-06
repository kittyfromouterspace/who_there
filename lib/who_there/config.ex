defmodule WhoThere.Config do
  @moduledoc """
  Configuration helpers for WhoThere.

  ## Database Configuration

  WhoThere uses `WhoThere.Repo` for database operations. You have two options:

  ### Option 1: Standalone Database (Development/Testing)

  Configure WhoThere.Repo directly:

      config :who_there, WhoThere.Repo,
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        database: "who_there_dev",
        pool_size: 10

  ### Option 2: Shared Database (Recommended for Production)

  Point WhoThere.Repo to use your app's database configuration:

      # In config/runtime.exs or config/prod.exs
      config :who_there, WhoThere.Repo,
        url: System.get_env("DATABASE_URL"),
        pool_size: 5

  ## Ash Domain Registration

  Add WhoThere.Domain to your ash_domains:

      config :my_app, ash_domains: [WhoThere.Domain, MyApp.Domain]

  ## Privacy and Feature Settings

      config :who_there,
        privacy_mode: false,        # Anonymize IP addresses
        bot_detection: true,        # Detect and flag bot traffic
        geographic_data: true,      # Collect geo data from headers
        session_tracking: true,     # Track sessions
        async_tracking: true        # Process tracking asynchronously
  """

  @doc """
  Returns the configured OTP app name.
  """
  def otp_app do
    Application.get_env(:who_there, :otp_app, :who_there)
  end

  @doc """
  Returns privacy mode setting.
  
  When true, IP addresses are anonymized before storage.
  """
  def privacy_mode? do
    Application.get_env(:who_there, :privacy_mode, false)
  end

  @doc """
  Returns whether bot detection is enabled.
  """
  def bot_detection? do
    Application.get_env(:who_there, :bot_detection, true)
  end

  @doc """
  Returns whether geographic data collection is enabled.
  """
  def geographic_data? do
    Application.get_env(:who_there, :geographic_data, true)
  end

  @doc """
  Returns whether session tracking is enabled.
  """
  def session_tracking? do
    Application.get_env(:who_there, :session_tracking, true)
  end

  @doc """
  Returns whether async tracking is enabled.
  """
  def async_tracking? do
    Application.get_env(:who_there, :async_tracking, true)
  end

  @doc """
  Returns the configured route filters.
  """
  def route_filters do
    Application.get_env(:who_there, :route_filters, [])
  end

  @doc """
  Returns paths to exclude from tracking.
  """
  def exclude_paths do
    Keyword.get(route_filters(), :exclude_paths, [
      ~r/^\/assets\//,
      ~r/^\/images\//,
      ~r/^\/_live\//,
      "/health",
      "/metrics"
    ])
  end
end
