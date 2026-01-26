defmodule LiveSchema.View.EventGeneratorTest do
  use ExUnit.Case, async: true

  # Helper to create test sockets
  defp new_socket(assigns) do
    %Phoenix.LiveView.Socket{
      id: "test-socket-#{:erlang.unique_integer()}",
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  # Test schema with various action types
  defmodule CounterState do
    use LiveSchema

    schema do
      field :count, :integer, default: 0
      field :name, :string, default: ""
      field :items, {:list, :integer}, default: []
    end

    # Action with no arguments
    action :increment do
      set_count(state, state.count + 1)
    end

    # Action with untyped argument (string passthrough)
    action :set_name, [:name] do
      set_name(state, name)
    end

    # Action with typed argument
    action :add_amount, amount: :integer do
      set_count(state, state.count + amount)
    end

    # Action with multiple typed arguments
    action :set_both, count: :integer, name: :string do
      state
      |> set_count(count)
      |> set_name(name)
    end
  end

  defmodule AsyncState do
    use LiveSchema

    schema do
      field :data, {:list, :string}, default: []
      field :loading, :boolean, default: false
    end

    action :clear do
      set_data(state, [])
    end

    async_action :load_data, filter: :atom do
      # Simulate async work
      data = ["item_#{filter}"]
      set_data(state, data)
    end
  end

  describe "single schema with generate_events" do
    defmodule SingleEventView do
      use LiveSchema.View,
        schema: LiveSchema.View.EventGeneratorTest.CounterState,
        generate_events: true
    end

    test "generates handle_event for action without arguments" do
      socket = new_socket(%{state: CounterState.new!()})

      assert {:noreply, socket} =
               SingleEventView.handle_event("CounterState:increment", %{}, socket)

      assert socket.assigns.state.count == 1
    end

    test "generates handle_event for action with untyped argument" do
      socket = new_socket(%{state: CounterState.new!()})

      assert {:noreply, socket} =
               SingleEventView.handle_event("CounterState:set_name", %{"name" => "hello"}, socket)

      assert socket.assigns.state.name == "hello"
    end

    test "generates handle_event for action with typed argument" do
      socket = new_socket(%{state: CounterState.new!()})

      assert {:noreply, socket} =
               SingleEventView.handle_event("CounterState:add_amount", %{"amount" => "5"}, socket)

      assert socket.assigns.state.count == 5
    end

    test "generates handle_event for action with multiple typed arguments" do
      socket = new_socket(%{state: CounterState.new!()})

      assert {:noreply, socket} =
               SingleEventView.handle_event(
                 "CounterState:set_both",
                 %{"count" => "42", "name" => "test"},
                 socket
               )

      assert socket.assigns.state.count == 42
      assert socket.assigns.state.name == "test"
    end
  end

  describe "multiple schemas with generate_events" do
    defmodule SidebarState do
      use LiveSchema

      schema do
        field :expanded, :boolean, default: true
        field :width, :integer, default: 250
      end

      action :toggle do
        set_expanded(state, !state.expanded)
      end

      action :set_width, width: :integer do
        set_width(state, width)
      end
    end

    defmodule MultiEventView do
      use LiveSchema.View,
        schemas: [
          counter: LiveSchema.View.EventGeneratorTest.CounterState,
          sidebar: LiveSchema.View.EventGeneratorTest.SidebarState
        ],
        generate_events: true
    end

    test "generates events for first schema with correct prefix" do
      socket =
        new_socket(%{
          counter: CounterState.new!(),
          sidebar: SidebarState.new!()
        })

      assert {:noreply, socket} =
               MultiEventView.handle_event("CounterState:increment", %{}, socket)

      assert socket.assigns.counter.count == 1
    end

    test "generates events for second schema with correct prefix" do
      socket =
        new_socket(%{
          counter: CounterState.new!(),
          sidebar: SidebarState.new!()
        })

      assert {:noreply, socket} = MultiEventView.handle_event("SidebarState:toggle", %{}, socket)
      assert socket.assigns.sidebar.expanded == false
    end

    test "typed arguments work with multiple schemas" do
      socket =
        new_socket(%{
          counter: CounterState.new!(),
          sidebar: SidebarState.new!()
        })

      assert {:noreply, socket} =
               MultiEventView.handle_event("SidebarState:set_width", %{"width" => "300"}, socket)

      assert socket.assigns.sidebar.width == 300
    end
  end

  describe "async action handling" do
    defmodule AsyncEventView do
      use LiveSchema.View,
        schema: LiveSchema.View.EventGeneratorTest.AsyncState,
        generate_events: true

      # Stub for start_async since we don't use Phoenix.LiveView in tests
      defp start_async(socket, _name, _work_fn), do: socket
    end

    test "generates handle_event for async action that returns start_async" do
      # The handle_event should call start_async
      # We can't fully test this without a real LiveView, but we can verify the pattern
      assert function_exported?(AsyncEventView, :handle_event, 3)
      assert function_exported?(AsyncEventView, :handle_async, 3)
    end

    test "generates handle_async for async action result" do
      socket = new_socket(%{state: AsyncState.new!()})
      new_state = AsyncState.set_data(AsyncState.new!(), ["loaded_data"])

      assert {:noreply, socket} =
               AsyncEventView.handle_async(:load_data, {:ok, new_state}, socket)

      assert socket.assigns.state.data == ["loaded_data"]
    end
  end

  describe "__actions__/0 introspection" do
    test "returns action metadata with typed arguments" do
      actions = CounterState.__actions__()

      assert {:increment, [], :sync} in actions
      assert {:set_name, [{:name, nil}], :sync} in actions
      assert {:add_amount, [{:amount, :integer}], :sync} in actions
      assert {:set_both, [{:count, :integer}, {:name, :string}], :sync} in actions
    end

    test "distinguishes sync and async actions" do
      actions = AsyncState.__actions__()

      assert {:clear, [], :sync} in actions
      assert {:load_data, [{:filter, :atom}], :async} in actions
    end
  end

  describe "user override behavior" do
    defmodule OverrideState do
      use LiveSchema

      schema do
        field :value, :integer, default: 0
      end

      action :set_value, value: :integer do
        set_value(state, value)
      end
    end

    defmodule OverrideView do
      use LiveSchema.View,
        schema: LiveSchema.View.EventGeneratorTest.OverrideState,
        generate_events: true

      # User-defined handler takes precedence due to pattern specificity
      def handle_event("OverrideState:set_value", %{"value" => "special"}, socket) do
        # Custom handling for special case
        {:noreply, apply_action(socket, {:set_value, 999})}
      end
    end

    test "user-defined handlers can override generated handlers with pattern matching" do
      socket = new_socket(%{state: OverrideState.new!()})

      # Special case uses user's handler
      assert {:noreply, socket} =
               OverrideView.handle_event(
                 "OverrideState:set_value",
                 %{"value" => "special"},
                 socket
               )

      assert socket.assigns.state.value == 999
    end

    test "generated handler is used when user handler pattern doesn't match" do
      socket = new_socket(%{state: OverrideState.new!()})

      # Normal case uses generated handler
      assert {:noreply, socket} =
               OverrideView.handle_event("OverrideState:set_value", %{"value" => "42"}, socket)

      assert socket.assigns.state.value == 42
    end
  end

  describe "generate_events: false (default)" do
    defmodule NoEventsView do
      use LiveSchema.View, schema: LiveSchema.View.EventGeneratorTest.CounterState
    end

    test "does not generate handle_event when generate_events is not set" do
      # The module shouldn't have handle_event/3 defined
      # (unless Phoenix defines it, so we check for our specific pattern)
      refute function_exported?(NoEventsView, :handle_event, 3)
    end
  end

  describe "reaction macro" do
    defmodule ReactionState do
      use LiveSchema

      schema do
        field :count, :integer, default: 0
        field :items, {:list, :map}, default: []
      end

      # Reaction with no arguments - read-only reply
      reaction :get_count do
        {state, %{count: state.count}}
      end

      # Reaction with typed argument
      reaction :get_item, id: :integer do
        item = Enum.find(state.items, &(&1.id == id))
        {state, %{item: item}}
      end

      # Reaction that modifies state and replies
      reaction :increment_and_get do
        new_state = set_count(state, state.count + 1)
        {new_state, %{count: new_state.count}}
      end

      # Reaction with multiple typed arguments
      reaction :add_and_get, amount: :integer, label: :string do
        new_state = set_count(state, state.count + amount)
        {new_state, %{count: new_state.count, label: label}}
      end
    end

    test "reaction returns {:reply, payload, new_state} from apply/2" do
      state = ReactionState.new!()

      assert {:reply, %{count: 0}, ^state} = ReactionState.apply(state, {:get_count})
    end

    test "reaction with argument returns reply" do
      state = ReactionState.new!(items: [%{id: 1, name: "first"}, %{id: 2, name: "second"}])

      assert {:reply, %{item: %{id: 2, name: "second"}}, ^state} =
               ReactionState.apply(state, {:get_item, 2})
    end

    test "reaction can modify state and reply" do
      state = ReactionState.new!(count: 5)

      assert {:reply, %{count: 6}, new_state} = ReactionState.apply(state, {:increment_and_get})
      assert new_state.count == 6
    end

    test "reaction with multiple typed arguments" do
      state = ReactionState.new!(count: 10)

      assert {:reply, %{count: 15, label: "added"}, new_state} =
               ReactionState.apply(state, {:add_and_get, 5, "added"})

      assert new_state.count == 15
    end

    test "__actions__/0 includes reactions with :reply type" do
      actions = ReactionState.__actions__()

      assert {:get_count, [], :reply} in actions
      assert {:get_item, [{:id, :integer}], :reply} in actions
      assert {:increment_and_get, [], :reply} in actions
      assert {:add_and_get, [{:amount, :integer}, {:label, :string}], :reply} in actions
    end
  end

  describe "reaction event generation" do
    defmodule ReactionEventView do
      use LiveSchema.View,
        schema: LiveSchema.View.EventGeneratorTest.ReactionState,
        generate_events: true
    end

    alias LiveSchema.View.EventGeneratorTest.ReactionState

    test "generates handle_event for reaction without arguments" do
      socket = new_socket(%{state: ReactionState.new!(count: 42)})

      assert {:reply, %{count: 42}, result_socket} =
               ReactionEventView.handle_event("ReactionState:get_count", %{}, socket)

      # State should remain unchanged
      assert result_socket.assigns.state.count == 42
    end

    test "generates handle_event for reaction with typed argument" do
      items = [%{id: 1, name: "first"}, %{id: 2, name: "second"}]
      socket = new_socket(%{state: ReactionState.new!(items: items)})

      assert {:reply, %{item: %{id: 2, name: "second"}}, _result_socket} =
               ReactionEventView.handle_event("ReactionState:get_item", %{"id" => "2"}, socket)
    end

    test "generates handle_event for reaction that modifies state" do
      socket = new_socket(%{state: ReactionState.new!(count: 10)})

      assert {:reply, %{count: 11}, result_socket} =
               ReactionEventView.handle_event("ReactionState:increment_and_get", %{}, socket)

      assert result_socket.assigns.state.count == 11
    end

    test "generates handle_event for reaction with multiple typed arguments" do
      socket = new_socket(%{state: ReactionState.new!(count: 5)})

      assert {:reply, %{count: 8, label: "test"}, result_socket} =
               ReactionEventView.handle_event(
                 "ReactionState:add_and_get",
                 %{"amount" => "3", "label" => "test"},
                 socket
               )

      assert result_socket.assigns.state.count == 8
    end
  end
end
