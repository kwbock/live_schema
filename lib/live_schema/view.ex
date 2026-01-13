defmodule LiveSchema.View do
  @moduledoc """
  Phoenix LiveView integration for LiveSchema.

  Provides helpers for using LiveSchema state in LiveView modules.

  ## Usage

      defmodule MyAppWeb.PostsLive do
        use MyAppWeb, :live_view
        use LiveSchema.View, schema: __MODULE__.State

        # State struct is defined in a nested module
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

        # The @state assign is automatically available
        def mount(_params, _session, socket) do
          {:ok, init_state(socket)}
        end

        def handle_event("load", _, socket) do
          {:noreply, apply_action(socket, {:load_posts})}
        end
      end

  ## Helpers Provided

  - `init_state/1` - Initialize `@state` with `Schema.new()`
  - `init_state/2` - Initialize with custom attributes
  - `apply_action/2` - Apply a reducer action to state
  - `update_state/2` - Update state with a function

  """

  @doc false
  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      @live_schema_module unquote(schema)

      import LiveSchema.View, only: [init_state: 1, init_state: 2, apply_action: 2, update_state: 2]

      @doc false
      def __live_schema__, do: @live_schema_module
    end
  end

  @doc """
  Initializes the state assign on the socket.

  ## Examples

      def mount(_params, _session, socket) do
        {:ok, init_state(socket)}
      end

  """
  defmacro init_state(socket) do
    quote do
      schema = @live_schema_module
      Phoenix.Component.assign(unquote(socket), :state, schema.new())
    end
  end

  @doc """
  Initializes the state assign with custom attributes.

  ## Examples

      def mount(_params, session, socket) do
        {:ok, init_state(socket, user: session["user"])}
      end

  """
  defmacro init_state(socket, attrs) do
    quote do
      schema = @live_schema_module
      Phoenix.Component.assign(unquote(socket), :state, schema.new!(unquote(attrs)))
    end
  end

  @doc """
  Applies a reducer action to the state.

  Updates the `@state` assign with the result.

  ## Examples

      def handle_event("select", %{"id" => id}, socket) do
        {:noreply, apply_action(socket, {:select_post, String.to_integer(id)})}
      end

  """
  defmacro apply_action(socket, action) do
    quote do
      socket = unquote(socket)
      schema = @live_schema_module
      current_state = socket.assigns.state
      new_state = schema.apply(current_state, unquote(action))

      # Emit telemetry
      :telemetry.execute(
        [:live_schema, :reducer, :applied],
        %{},
        %{
          schema: schema,
          action: elem(unquote(action), 0),
          socket_id: socket.id
        }
      )

      Phoenix.Component.assign(socket, :state, new_state)
    end
  end

  @doc """
  Updates the state using a function.

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
end
