defmodule LiveSchema.View do
  @moduledoc """
  Phoenix LiveView integration for LiveSchema.

  Provides helpers for using LiveSchema state in LiveView modules.

  ## Single Schema Usage

      defmodule MyAppWeb.PostsLive do
        use MyAppWeb, :live_view
        use LiveSchema.View, schema: __MODULE__.State

        defmodule State do
          use LiveSchema

          schema do
            field :posts, {:list, {:struct, Post}}, default: []
            field :loading, :boolean, default: false
          end

          reducer :load_posts do
            set_loading(state, true)
          end
        end

        def mount(_params, _session, socket) do
          {:ok, init_state(socket)}
        end

        def handle_event("load", _, socket) do
          {:noreply, apply_action(socket, {:load_posts})}
        end
      end

  ## Multiple Schema Usage

  You can register multiple schemas with different assign keys:

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        use LiveSchema.View, schemas: [
          state: __MODULE__.MainState,
          sidebar: __MODULE__.SidebarState
        ]

        defmodule MainState do
          use LiveSchema
          schema do
            field :data, {:list, :map}, default: []
          end
        end

        defmodule SidebarState do
          use LiveSchema
          schema do
            field :expanded, :boolean, default: true
          end

          reducer :toggle do
            set_expanded(state, !state.expanded)
          end
        end

        def mount(_params, _session, socket) do
          socket =
            socket
            |> init_state(:state)
            |> init_state(:sidebar)

          {:ok, socket}
        end

        def handle_event("toggle_sidebar", _, socket) do
          {:noreply, apply_action(socket, :sidebar, {:toggle})}
        end
      end

  ## Helpers Provided

  - `init_state/1` - Initialize default `:state` with `Schema.new()`
  - `init_state/2` - Initialize with assign key or custom attributes
  - `init_state/3` - Initialize specific assign with custom attributes
  - `apply_action/2` - Apply a reducer action to default `:state`
  - `apply_action/3` - Apply a reducer action to specific assign
  - `update_state/2` - Update default `:state` with a function
  - `update_state/3` - Update specific assign with a function

  """

  @doc false
  defmacro __using__(opts) do
    schemas =
      cond do
        Keyword.has_key?(opts, :schemas) ->
          Keyword.fetch!(opts, :schemas)

        Keyword.has_key?(opts, :schema) ->
          [state: Keyword.fetch!(opts, :schema)]

        true ->
          raise ArgumentError, "LiveSchema.View requires either :schema or :schemas option"
      end

    # Build a list of {key, module} pairs that can be properly unquoted
    schemas_pairs =
      Enum.map(schemas, fn {key, mod} ->
        {key, mod}
      end)

    quote do
      @live_schemas Map.new(unquote(schemas_pairs))

      import LiveSchema.View,
        only: [
          init_state: 1,
          init_state: 2,
          init_state: 3,
          apply_action: 2,
          apply_action: 3,
          update_state: 2,
          update_state: 3
        ]

      @doc false
      def __live_schemas__, do: @live_schemas

      # Backwards compatibility
      @doc false
      def __live_schema__, do: @live_schemas[:state]
    end
  end

  @doc """
  Initializes the default `:state` assign on the socket.

  ## Examples

      def mount(_params, _session, socket) do
        {:ok, init_state(socket)}
      end

  """
  defmacro init_state(socket) do
    quote do
      schema = @live_schemas[:state]
      Phoenix.Component.assign(unquote(socket), :state, schema.new())
    end
  end

  @doc """
  Initializes a state assign on the socket.

  When passed an atom, initializes the corresponding schema at that assign key.
  When passed a keyword list, initializes the default `:state` with those attributes.

  ## Examples

      # Initialize a specific assign
      def mount(_params, _session, socket) do
        socket =
          socket
          |> init_state(:state)
          |> init_state(:sidebar)

        {:ok, socket}
      end

      # Initialize default :state with attributes (backwards compatible)
      def mount(_params, session, socket) do
        {:ok, init_state(socket, user: session["user"])}
      end

  """
  defmacro init_state(socket, assign_key_or_attrs)

  defmacro init_state(socket, assign_key) when is_atom(assign_key) do
    quote do
      schema = @live_schemas[unquote(assign_key)]

      if is_nil(schema) do
        raise ArgumentError,
              "No schema registered for assign key #{inspect(unquote(assign_key))}. " <>
                "Available keys: #{inspect(Map.keys(@live_schemas))}"
      end

      Phoenix.Component.assign(unquote(socket), unquote(assign_key), schema.new())
    end
  end

  defmacro init_state(socket, attrs) do
    quote do
      schema = @live_schemas[:state]
      Phoenix.Component.assign(unquote(socket), :state, schema.new!(unquote(attrs)))
    end
  end

  @doc """
  Initializes a specific assign with custom attributes.

  ## Examples

      def mount(_params, session, socket) do
        {:ok, init_state(socket, :sidebar, expanded: false)}
      end

  """
  defmacro init_state(socket, assign_key, attrs) when is_atom(assign_key) do
    quote do
      schema = @live_schemas[unquote(assign_key)]

      if is_nil(schema) do
        raise ArgumentError,
              "No schema registered for assign key #{inspect(unquote(assign_key))}. " <>
                "Available keys: #{inspect(Map.keys(@live_schemas))}"
      end

      Phoenix.Component.assign(unquote(socket), unquote(assign_key), schema.new!(unquote(attrs)))
    end
  end

  @doc """
  Applies a reducer action to the default `:state` assign.

  Updates the `@state` assign with the result.

  ## Examples

      def handle_event("select", %{"id" => id}, socket) do
        {:noreply, apply_action(socket, {:select_post, String.to_integer(id)})}
      end

  """
  defmacro apply_action(socket, action) do
    quote do
      socket = unquote(socket)
      schema = @live_schemas[:state]
      current_state = socket.assigns.state
      new_state = schema.apply(current_state, unquote(action))

      # Emit telemetry
      :telemetry.execute(
        [:live_schema, :reducer, :applied],
        %{},
        %{
          schema: schema,
          action: elem(unquote(action), 0),
          assign_key: :state,
          socket_id: socket.id
        }
      )

      Phoenix.Component.assign(socket, :state, new_state)
    end
  end

  @doc """
  Applies a reducer action to a specific assign.

  ## Examples

      def handle_event("toggle_sidebar", _, socket) do
        {:noreply, apply_action(socket, :sidebar, {:toggle})}
      end

  """
  defmacro apply_action(socket, assign_key, action) when is_atom(assign_key) do
    quote do
      socket = unquote(socket)
      assign_key = unquote(assign_key)
      schema = @live_schemas[assign_key]

      if is_nil(schema) do
        raise ArgumentError,
              "No schema registered for assign key #{inspect(assign_key)}. " <>
                "Available keys: #{inspect(Map.keys(@live_schemas))}"
      end

      current_state = Map.fetch!(socket.assigns, assign_key)
      new_state = schema.apply(current_state, unquote(action))

      # Emit telemetry
      :telemetry.execute(
        [:live_schema, :reducer, :applied],
        %{},
        %{
          schema: schema,
          action: elem(unquote(action), 0),
          assign_key: assign_key,
          socket_id: socket.id
        }
      )

      Phoenix.Component.assign(socket, assign_key, new_state)
    end
  end

  @doc """
  Updates the default `:state` assign using a function.

  ## Examples

      def handle_info({:new_post, post}, socket) do
        {:noreply, update_state(socket, fn state ->
          State.set_posts(state, [post | state.posts])
        end)}
      end

  """
  defmacro update_state(socket, fun) do
    quote do
      socket = unquote(socket)
      current_state = socket.assigns.state
      new_state = unquote(fun).(current_state)
      Phoenix.Component.assign(socket, :state, new_state)
    end
  end

  @doc """
  Updates a specific assign using a function.

  ## Examples

      def handle_info(:collapse_sidebar, socket) do
        {:noreply, update_state(socket, :sidebar, fn state ->
          SidebarState.set_expanded(state, false)
        end)}
      end

  """
  defmacro update_state(socket, assign_key, fun) when is_atom(assign_key) do
    quote do
      socket = unquote(socket)
      assign_key = unquote(assign_key)
      current_state = Map.fetch!(socket.assigns, assign_key)
      new_state = unquote(fun).(current_state)
      Phoenix.Component.assign(socket, assign_key, new_state)
    end
  end
end
