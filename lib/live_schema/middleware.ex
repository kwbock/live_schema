defmodule LiveSchema.Middleware do
  @moduledoc """
  Middleware/hook system for actions.

  Middleware allows you to run code before and after actions,
  useful for logging, persistence, analytics, and other cross-cutting concerns.

  ## Usage

      defmodule MyApp.State do
        use LiveSchema

        before_action :log_action
        after_action :persist_state
        after_action :emit_telemetry

        schema do
          field :count, :integer, default: 0
        end

        action :increment do
          set_count(state, state.count + 1)
        end

        defp log_action(state, action) do
          Logger.debug("Action: \#{inspect(action)}")
        end

        defp persist_state(old_state, new_state, action) do
          MyApp.StateCache.put(new_state)
        end

        defp emit_telemetry(old_state, new_state, action) do
          :telemetry.execute(
            [:my_app, :state, :changed],
            %{},
            %{action: elem(action, 0), module: __MODULE__}
          )
        end
      end

  ## Hook Signatures

  - `before_action` hooks receive: `(state, action)` - called before the action
  - `after_action` hooks receive: `(old_state, new_state, action)` - called after

  Hooks cannot modify the state - they are for side effects only.
  """

  @doc """
  Registers a function to run before each action.

  The function receives the current state and the action tuple.

  ## Example

      before_action :log_action

      defp log_action(state, action) do
        Logger.info("Dispatching \#{inspect(action)}")
      end

  """
  defmacro before_action(function_name) when is_atom(function_name) do
    quote do
      @live_schema_before_hooks unquote(function_name)
    end
  end

  @doc """
  Registers a function to run after each action.

  The function receives the old state, new state, and action tuple.

  ## Example

      after_action :track_change

      defp track_change(old_state, new_state, action) do
        if old_state.count != new_state.count do
          Analytics.track("count_changed", %{
            old: old_state.count,
            new: new_state.count,
            action: elem(action, 0)
          })
        end
      end

  """
  defmacro after_action(function_name) when is_atom(function_name) do
    quote do
      @live_schema_after_hooks unquote(function_name)
    end
  end
end
