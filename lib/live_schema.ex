defmodule LiveSchema do
  @moduledoc """
  A comprehensive state management library for Phoenix LiveView.

  LiveSchema provides a DSL for defining typed state structures with automatic
  setter generation, action-based state transitions, and deep Phoenix integration.

  ## Quick Start

  Define a state schema:

      defmodule MyApp.PostsState do
        use LiveSchema

        schema do
          field :posts, {:list, Post}, default: []
          field :selected, {:nullable, Post}
          field :loading, :boolean, default: false

          embeds_one :filter do
            field :status, {:enum, [:all, :active]}, default: :all
            field :query, :string, default: ""
          end
        end

        action :select_post, [:id] do
          post = Enum.find(state.posts, &(&1.id == id))
          set_selected(state, post)
        end
      end

  ## Features

  - **Schema DSL** - Define your state structure declaratively
  - **Type System** - Built-in types with optional runtime validation
  - **Auto-generated Setters** - Reduce boilerplate
  - **Actions** - Elm-style state transitions
  - **Embeds** - Nested state structures
  - **Phoenix Integration** - Works with LiveView and Components

  ## Configuration

  Configure LiveSchema in your `config.exs`:

      config :live_schema,
        validate_at: :runtime,  # :runtime | :none
        on_error: :log          # :log | :raise | :ignore

  """

  @doc false
  defmacro __using__(opts) do
    quote do
      import LiveSchema.Schema,
        only: [
          schema: 1,
          field: 2,
          field: 3,
          embeds_one: 2,
          embeds_one: 3,
          embeds_many: 2,
          embeds_many: 3
        ]

      import LiveSchema.Action,
        only: [action: 2, action: 3, async_action: 2, async_action: 3, reaction: 2, reaction: 3]

      import LiveSchema.Middleware, only: [before_action: 1, after_action: 1]

      @live_schema_opts unquote(opts)

      Module.register_attribute(__MODULE__, :live_schema_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :live_schema_embeds, accumulate: true)
      Module.register_attribute(__MODULE__, :live_schema_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :live_schema_before_hooks, accumulate: true)
      Module.register_attribute(__MODULE__, :live_schema_after_hooks, accumulate: true)

      @before_compile LiveSchema.Compiler
    end
  end

  @doc """
  Computes the difference between two states.

  Returns a map describing what changed between the old and new state.

  ## Example

      {:changed, diff} = LiveSchema.diff(old_state, new_state)
      # diff = %{
      #   changed: [:posts, :selected],
      #   added: %{selected: post},
      #   removed: %{},
      #   nested: %{filter: %{changed: [:status]}}
      # }

  """
  defdelegate diff(old_state, new_state), to: LiveSchema.Diff
end
