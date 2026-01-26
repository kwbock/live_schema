defmodule LiveSchema.ViewTest do
  use ExUnit.Case, async: false

  # async: false because we test telemetry which uses global handlers

  # Test schemas
  defmodule MainState do
    use LiveSchema

    schema do
      field :count, :integer, default: 0
      field :name, :string, default: ""
    end

    action :increment do
      set_count(state, state.count + 1)
    end

    action :set_name, [:name] do
      set_name(state, name)
    end
  end

  defmodule SidebarState do
    use LiveSchema

    schema do
      field :expanded, :boolean, default: true
      field :width, :integer, default: 250
    end

    action :toggle do
      set_expanded(state, !state.expanded)
    end

    action :set_width, [:width] do
      set_width(state, width)
    end
  end

  defmodule ModalState do
    use LiveSchema

    schema do
      field :open, :boolean, default: false
      field :title, :string, default: ""
    end

    action :open, [:title] do
      state
      |> set_open(true)
      |> set_title(title)
    end

    action :close do
      state
      |> set_open(false)
      |> set_title("")
    end
  end

  # Helper to create test sockets
  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      id: "test-socket-#{:erlang.unique_integer()}",
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  # Single schema view module (backwards compatibility)
  defmodule SingleSchemaView do
    use LiveSchema.View, schema: LiveSchema.ViewTest.MainState
  end

  # Multiple schema view module
  defmodule MultiSchemaView do
    use LiveSchema.View,
      schemas: [
        state: LiveSchema.ViewTest.MainState,
        sidebar: LiveSchema.ViewTest.SidebarState,
        modal: LiveSchema.ViewTest.ModalState
      ]
  end

  describe "single schema (backwards compatibility)" do
    test "__live_schema__/0 returns the schema module" do
      assert SingleSchemaView.__live_schema__() == MainState
    end

    test "__live_schemas__/0 returns map with :state key" do
      assert SingleSchemaView.__live_schemas__() == %{state: MainState}
    end
  end

  describe "multiple schemas" do
    test "__live_schemas__/0 returns all registered schemas" do
      schemas = MultiSchemaView.__live_schemas__()

      assert schemas[:state] == MainState
      assert schemas[:sidebar] == SidebarState
      assert schemas[:modal] == ModalState
    end

    test "__live_schema__/0 returns the :state schema for backwards compat" do
      assert MultiSchemaView.__live_schema__() == MainState
    end
  end

  describe "init_state/1" do
    defmodule InitState1View do
      use LiveSchema.View, schema: LiveSchema.ViewTest.MainState

      def test_init(socket) do
        init_state(socket)
      end
    end

    test "initializes default :state assign" do
      socket = new_socket()
      socket = InitState1View.test_init(socket)

      assert %MainState{} = socket.assigns.state
      assert socket.assigns.state.count == 0
      assert socket.assigns.state.name == ""
    end
  end

  describe "init_state/2 with assign key" do
    defmodule InitState2KeyView do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState
        ]

      def test_init_state(socket) do
        init_state(socket, :state)
      end

      def test_init_sidebar(socket) do
        init_state(socket, :sidebar)
      end
    end

    test "initializes specific assign by key" do
      socket = new_socket()

      socket = InitState2KeyView.test_init_sidebar(socket)

      assert %SidebarState{} = socket.assigns.sidebar
      assert socket.assigns.sidebar.expanded == true
      assert socket.assigns.sidebar.width == 250
    end

    test "initializes :state assign explicitly" do
      socket = new_socket()

      socket = InitState2KeyView.test_init_state(socket)

      assert %MainState{} = socket.assigns.state
    end
  end

  describe "init_state/2 with attrs (backwards compat)" do
    defmodule InitState2AttrsView do
      use LiveSchema.View, schema: LiveSchema.ViewTest.MainState

      def test_init_with_attrs(socket, attrs) do
        init_state(socket, attrs)
      end
    end

    test "initializes :state with custom attributes" do
      socket = new_socket()

      socket = InitState2AttrsView.test_init_with_attrs(socket, count: 10, name: "test")

      assert socket.assigns.state.count == 10
      assert socket.assigns.state.name == "test"
    end
  end

  describe "init_state/3" do
    defmodule InitState3View do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState
        ]

      def test_init_sidebar_with_attrs(socket, attrs) do
        init_state(socket, :sidebar, attrs)
      end
    end

    test "initializes specific assign with custom attributes" do
      socket = new_socket()

      socket = InitState3View.test_init_sidebar_with_attrs(socket, expanded: false, width: 300)

      assert socket.assigns.sidebar.expanded == false
      assert socket.assigns.sidebar.width == 300
    end
  end

  describe "apply_action/2" do
    defmodule ApplyAction2View do
      use LiveSchema.View, schema: LiveSchema.ViewTest.MainState

      def test_increment(socket) do
        apply_action(socket, {:increment})
      end

      def test_set_name(socket, name) do
        apply_action(socket, {:set_name, name})
      end
    end

    test "applies action to default :state assign" do
      socket = new_socket(%{state: MainState.new!()})

      socket = ApplyAction2View.test_increment(socket)

      assert socket.assigns.state.count == 1
    end

    test "applies action with arguments" do
      socket = new_socket(%{state: MainState.new!()})

      socket = ApplyAction2View.test_set_name(socket, "hello")

      assert socket.assigns.state.name == "hello"
    end
  end

  describe "apply_action/3" do
    defmodule ApplyAction3View do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState,
          modal: LiveSchema.ViewTest.ModalState
        ]

      def test_toggle_sidebar(socket) do
        apply_action(socket, :sidebar, {:toggle})
      end

      def test_open_modal(socket, title) do
        apply_action(socket, :modal, {:open, title})
      end

      def test_increment_state(socket) do
        apply_action(socket, :state, {:increment})
      end
    end

    test "applies action to specific assign" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!(),
          modal: ModalState.new!()
        })

      socket = ApplyAction3View.test_toggle_sidebar(socket)

      assert socket.assigns.sidebar.expanded == false
      # Other assigns unchanged
      assert socket.assigns.state.count == 0
      assert socket.assigns.modal.open == false
    end

    test "applies action with arguments to specific assign" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!(),
          modal: ModalState.new!()
        })

      socket = ApplyAction3View.test_open_modal(socket, "Confirm Delete")

      assert socket.assigns.modal.open == true
      assert socket.assigns.modal.title == "Confirm Delete"
    end

    test "can explicitly target :state assign" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!()
        })

      socket = ApplyAction3View.test_increment_state(socket)

      assert socket.assigns.state.count == 1
    end
  end

  describe "update_state/2" do
    defmodule UpdateState2View do
      use LiveSchema.View, schema: LiveSchema.ViewTest.MainState

      def test_update(socket) do
        update_state(socket, fn state ->
          MainState.set_count(state, state.count + 10)
        end)
      end
    end

    test "updates default :state with function" do
      socket = new_socket(%{state: MainState.new!(count: 5)})

      socket = UpdateState2View.test_update(socket)

      assert socket.assigns.state.count == 15
    end
  end

  describe "update_state/3" do
    defmodule UpdateState3View do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState
        ]

      def test_update_sidebar(socket) do
        update_state(socket, :sidebar, fn state ->
          SidebarState.set_width(state, state.width * 2)
        end)
      end
    end

    test "updates specific assign with function" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!(width: 100)
        })

      socket = UpdateState3View.test_update_sidebar(socket)

      assert socket.assigns.sidebar.width == 200
    end
  end

  describe "error handling" do
    defmodule ErrorView do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState
        ]

      def test_init_unknown(socket) do
        init_state(socket, :unknown_key)
      end

      def test_apply_unknown(socket) do
        apply_action(socket, :unknown_key, {:some_action})
      end
    end

    test "init_state raises for unregistered assign key" do
      socket = new_socket()

      assert_raise ArgumentError, ~r/No schema registered for assign key :unknown_key/, fn ->
        ErrorView.test_init_unknown(socket)
      end
    end

    test "apply_action raises for unregistered assign key" do
      socket = new_socket(%{state: MainState.new!()})

      assert_raise ArgumentError, ~r/No schema registered for assign key :unknown_key/, fn ->
        ErrorView.test_apply_unknown(socket)
      end
    end
  end

  describe "telemetry" do
    defmodule TelemetryView do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState
        ]

      def test_apply_state(socket) do
        apply_action(socket, {:increment})
      end

      def test_apply_sidebar(socket) do
        apply_action(socket, :sidebar, {:toggle})
      end
    end

    # Module function for telemetry handler
    def handle_telemetry_event(event, measurements, metadata, config) do
      test_pid = config[:test_pid]
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end

    setup do
      test_pid = self()
      handler_id = "view-test-handler-#{:erlang.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:live_schema, :action, :applied],
        &__MODULE__.handle_telemetry_event/4,
        %{test_pid: test_pid}
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      {:ok, handler_id: handler_id}
    end

    test "emits telemetry with assign_key for default :state" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!()
        })

      TelemetryView.test_apply_state(socket)

      assert_receive {:telemetry_event, [:live_schema, :action, :applied], _, metadata}
      assert metadata.assign_key == :state
      assert metadata.action == :increment
      assert metadata.schema == MainState
    end

    test "emits telemetry with assign_key for specific assign" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!()
        })

      TelemetryView.test_apply_sidebar(socket)

      assert_receive {:telemetry_event, [:live_schema, :action, :applied], _, metadata}
      assert metadata.assign_key == :sidebar
      assert metadata.action == :toggle
      assert metadata.schema == SidebarState
    end
  end

  describe "chained operations" do
    defmodule ChainedView do
      use LiveSchema.View,
        schemas: [
          state: LiveSchema.ViewTest.MainState,
          sidebar: LiveSchema.ViewTest.SidebarState,
          modal: LiveSchema.ViewTest.ModalState
        ]

      def test_init_all(socket) do
        socket
        |> init_state(:state)
        |> init_state(:sidebar)
        |> init_state(:modal)
      end

      def test_complex_operation(socket) do
        socket
        |> apply_action(:state, {:increment})
        |> apply_action(:sidebar, {:toggle})
        |> apply_action(:modal, {:open, "Test Modal"})
      end
    end

    test "can chain init_state calls" do
      socket = new_socket()

      socket = ChainedView.test_init_all(socket)

      assert %MainState{} = socket.assigns.state
      assert %SidebarState{} = socket.assigns.sidebar
      assert %ModalState{} = socket.assigns.modal
    end

    test "can chain apply_action calls across different assigns" do
      socket =
        new_socket(%{
          state: MainState.new!(),
          sidebar: SidebarState.new!(),
          modal: ModalState.new!()
        })

      socket = ChainedView.test_complex_operation(socket)

      assert socket.assigns.state.count == 1
      assert socket.assigns.sidebar.expanded == false
      assert socket.assigns.modal.open == true
      assert socket.assigns.modal.title == "Test Modal"
    end
  end

  describe "use without options" do
    test "raises ArgumentError when neither schema nor schemas provided" do
      assert_raise ArgumentError, ~r/requires either :schema or :schemas option/, fn ->
        defmodule InvalidView do
          use LiveSchema.View
        end
      end
    end
  end
end
