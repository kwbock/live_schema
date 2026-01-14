defmodule LiveSchema.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kwbock/live_schema"

  def project do
    [
      app: :live_schema,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Optional Phoenix/LiveView dependencies
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 0.20", optional: true},

      # Telemetry for observability
      {:telemetry, "~> 1.0"},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp description do
    """
    A comprehensive state management library for Phoenix LiveView with DSL,
    type checking, and deep Phoenix integration.
    """
  end

  defp package do
    [
      name: "live_schema",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "LiveSchema",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/getting-started.md",
        "guides/schema-dsl.md",
        "guides/reducers.md",
        "guides/validation.md",
        "guides/phoenix-integration.md",
        "guides/testing.md",
        "guides/migration.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          LiveSchema,
          LiveSchema.Schema,
          LiveSchema.Types
        ],
        Validation: [
          LiveSchema.Validation,
          LiveSchema.Validators
        ],
        "Phoenix Integration": [
          LiveSchema.View
        ],
        Testing: [
          LiveSchema.Test
        ],
        Errors: [
          LiveSchema.CompileError,
          LiveSchema.TypeError,
          LiveSchema.ActionError,
          LiveSchema.ValidationError
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:phoenix, :phoenix_live_view]
    ]
  end
end
