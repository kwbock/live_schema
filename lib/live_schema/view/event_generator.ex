defmodule LiveSchema.View.EventGenerator do
  @moduledoc """
  Generates `handle_event/3` callbacks for LiveSchema actions.

  This module is used as a `@before_compile` hook to automatically generate
  event handlers based on actions defined in registered schemas.

  ## Event Naming

  Events are named using the pattern `"ModuleName:action_name"` where
  `ModuleName` is the last segment of the schema module name:

  - `MyApp.PostsLive.State` -> `"State:increment"`
  - `MyApp.SidebarState` -> `"SidebarState:toggle"`

  ## Generated Handlers

  For sync actions:

      def handle_event("State:increment", _params, socket) do
        {:noreply, apply_action(socket, {:increment})}
      end

  For actions with typed arguments:

      def handle_event("State:select", params, socket) do
        id = LiveSchema.View.Coerce.coerce(params["id"], :integer)
        {:noreply, apply_action(socket, {:select, id})}
      end

  For async actions:

      def handle_event("State:load_posts", params, socket) do
        filter = LiveSchema.View.Coerce.coerce(params["filter"], :atom)
        {:async, work_fn} = @live_schemas[:state].apply(socket.assigns.state, {:load_posts, filter})
        {:noreply, start_async(socket, :load_posts, work_fn)}
      end

      def handle_async(:load_posts, {:ok, new_state}, socket) do
        {:noreply, assign(socket, :state, new_state)}
      end

  For reactions (reply actions):

      def handle_event("State:get_count", _params, socket) do
        {:reply, payload, new_state} = State.apply(socket.assigns.state, {:get_count})
        {:reply, payload, assign(socket, :state, new_state)}
      end

  """

  @doc false
  defmacro __before_compile__(env) do
    schemas = Module.get_attribute(env.module, :live_schemas)

    if schemas == nil or map_size(schemas) == 0 do
      quote do
      end
    else
      handlers = generate_all_handlers(schemas)

      quote do
        (unquote_splicing(handlers))
      end
    end
  end

  defp generate_all_handlers(schemas) do
    schemas
    |> Enum.flat_map(fn {assign_key, schema_module} ->
      generate_handlers_for_schema(assign_key, schema_module)
    end)
  end

  defp generate_handlers_for_schema(assign_key, schema_module) do
    # Get the event prefix from the module name
    prefix = event_prefix(schema_module)

    # Get actions from the schema module
    actions = get_actions(schema_module)

    # Generate handlers for each action
    sync_handlers =
      actions
      |> Enum.filter(fn {_name, _args, type} -> type == :sync end)
      |> Enum.map(fn {name, args, _type} ->
        generate_sync_handler(prefix, assign_key, name, args)
      end)

    async_handlers =
      actions
      |> Enum.filter(fn {_name, _args, type} -> type == :async end)
      |> Enum.flat_map(fn {name, args, _type} ->
        generate_async_handlers(prefix, assign_key, schema_module, name, args)
      end)

    reply_handlers =
      actions
      |> Enum.filter(fn {_name, _args, type} -> type == :reply end)
      |> Enum.map(fn {name, args, _type} ->
        generate_reply_handler(prefix, assign_key, schema_module, name, args)
      end)

    sync_handlers ++ async_handlers ++ reply_handlers
  end

  defp event_prefix(module) do
    module |> Module.split() |> List.last()
  end

  defp get_actions(schema_module) do
    if function_exported?(schema_module, :__actions__, 0) do
      schema_module.__actions__()
    else
      []
    end
  end

  defp generate_sync_handler(prefix, assign_key, action_name, args) do
    event_name = "#{prefix}:#{action_name}"

    if Enum.empty?(args) do
      # No arguments - simple handler
      if assign_key == :state do
        quote do
          def handle_event(unquote(event_name), _params, socket) do
            {:noreply, apply_action(socket, {unquote(action_name)})}
          end
        end
      else
        quote do
          def handle_event(unquote(event_name), _params, socket) do
            {:noreply, apply_action(socket, unquote(assign_key), {unquote(action_name)})}
          end
        end
      end
    else
      # Has arguments - coerce and build action tuple
      coerce_statements = generate_coerce_statements(args)
      action_tuple = build_action_tuple(action_name, args)

      if assign_key == :state do
        quote do
          def handle_event(unquote(event_name), params, socket) do
            unquote_splicing(coerce_statements)
            {:noreply, apply_action(socket, unquote(action_tuple))}
          end
        end
      else
        quote do
          def handle_event(unquote(event_name), params, socket) do
            unquote_splicing(coerce_statements)
            {:noreply, apply_action(socket, unquote(assign_key), unquote(action_tuple))}
          end
        end
      end
    end
  end

  defp generate_async_handlers(prefix, assign_key, schema_module, action_name, args) do
    event_name = "#{prefix}:#{action_name}"

    # Handle event handler
    handle_event =
      if Enum.empty?(args) do
        quote do
          def handle_event(unquote(event_name), _params, socket) do
            current_state = Map.fetch!(socket.assigns, unquote(assign_key))

            {:async, work_fn} =
              unquote(schema_module).apply(current_state, {unquote(action_name)})

            {:noreply, start_async(socket, unquote(action_name), work_fn)}
          end
        end
      else
        coerce_statements = generate_coerce_statements(args)
        action_tuple = build_action_tuple(action_name, args)

        quote do
          def handle_event(unquote(event_name), params, socket) do
            unquote_splicing(coerce_statements)
            current_state = Map.fetch!(socket.assigns, unquote(assign_key))
            {:async, work_fn} = unquote(schema_module).apply(current_state, unquote(action_tuple))
            {:noreply, start_async(socket, unquote(action_name), work_fn)}
          end
        end
      end

    # Handle async result handler
    handle_async =
      quote do
        def handle_async(unquote(action_name), {:ok, new_state}, socket) do
          {:noreply, Phoenix.Component.assign(socket, unquote(assign_key), new_state)}
        end
      end

    [handle_event, handle_async]
  end

  defp generate_reply_handler(prefix, assign_key, schema_module, action_name, args) do
    event_name = "#{prefix}:#{action_name}"

    if Enum.empty?(args) do
      quote do
        def handle_event(unquote(event_name), _params, socket) do
          current_state = Map.fetch!(socket.assigns, unquote(assign_key))

          {:reply, payload, new_state} =
            unquote(schema_module).apply(current_state, {unquote(action_name)})

          {:reply, payload, Phoenix.Component.assign(socket, unquote(assign_key), new_state)}
        end
      end
    else
      coerce_statements = generate_coerce_statements(args)
      action_tuple = build_action_tuple(action_name, args)

      quote do
        def handle_event(unquote(event_name), params, socket) do
          unquote_splicing(coerce_statements)
          current_state = Map.fetch!(socket.assigns, unquote(assign_key))

          {:reply, payload, new_state} =
            unquote(schema_module).apply(current_state, unquote(action_tuple))

          {:reply, payload, Phoenix.Component.assign(socket, unquote(assign_key), new_state)}
        end
      end
    end
  end

  defp generate_coerce_statements(args) do
    Enum.map(args, fn {arg_name, arg_type} ->
      arg_var = Macro.var(arg_name, nil)
      arg_key = to_string(arg_name)

      quote do
        unquote(arg_var) =
          LiveSchema.View.Coerce.coerce(params[unquote(arg_key)], unquote(arg_type))
      end
    end)
  end

  defp build_action_tuple(action_name, args) do
    arg_vars = Enum.map(args, fn {arg_name, _type} -> Macro.var(arg_name, nil) end)
    {:{}, [], [action_name | arg_vars]}
  end
end
