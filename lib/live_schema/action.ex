defmodule LiveSchema.Action do
  @moduledoc """
  Macros for defining action-based state transitions.

  Actions provide an Elm-style pattern for state management where all
  state transitions are explicit and go through a central `apply/2` function.

  ## Basic Usage

      defmodule MyApp.State do
        use LiveSchema

        schema do
          field :count, :integer, default: 0
          field :posts, {:list, {:struct, Post}}, default: []
        end

        action :increment do
          set_count(state, state.count + 1)
        end

        action :select_post, [:id] do
          post = Enum.find(state.posts, &(&1.id == id))
          set_selected(state, post)
        end
      end

  ## With Guards

      action :increment, [:amount] when is_integer(amount) and amount > 0 do
        set_count(state, state.count + amount)
      end

  ## Async Actions

  For operations that need to perform async work:

      async_action :load_posts, [:filter] do
        posts = MyApp.Posts.list(filter)
        set_posts(state, posts)
      end

  This generates a function that returns `{:async, fun}` for use with
  LiveView's `start_async/3`.

  ## Reactions

  For actions that need to reply to the client:

      reaction :get_count do
        {state, %{count: state.count}}
      end

      reaction :increment_and_get do
        new_state = set_count(state, state.count + 1)
        {new_state, %{count: new_state.count}}
      end

  This generates a function that returns `{:reply, payload, new_state}` for use
  with LiveView's `{:reply, payload, socket}` return value.

  """

  @doc """
  Defines a synchronous action.

  The action body has access to:
  - `state` - The current state struct
  - Any arguments specified in the args list

  ## Examples

      # No arguments
      action :reset do
        MyApp.State.new()
      end

      # With untyped arguments (strings passed through)
      action :set_filter, [:field, :value] do
        update_in(state.filter, &Map.put(&1, field, value))
      end

      # With typed arguments (auto-coerced when using generate_events: true)
      action :select_post, [id: :integer] do
        set_selected_id(state, id)
      end

      # With multiple typed arguments
      action :set_range, [min: :integer, max: :integer] do
        state |> set_min(min) |> set_max(max)
      end

      # With guards
      action :add, [:n] when is_integer(n) and n > 0 do
        set_count(state, state.count + n)
      end

  ## Typed Arguments

  When using `LiveSchema.View` with `generate_events: true`, typed arguments
  are automatically coerced from string parameters:

  - `:integer` - Parses to integer
  - `:float` - Parses to float
  - `:boolean` - Converts "true"/"false" strings
  - `:atom` - Converts to existing atom
  - `:string` - Ensures string output
  - Untyped (list format) - Passthrough (no coercion)

  """
  defmacro action(name, args \\ [], do: block) do
    {args, guards} = extract_guards(args)
    {arg_names, arg_types} = extract_args_with_types(args)

    quote do
      @live_schema_actions {unquote(name), unquote(arg_types), :sync}

      unquote(generate_action_clause(name, arg_names, guards, block))
    end
  end

  @doc """
  Defines an asynchronous action.

  Async actions return `{:async, fun}` where `fun` is a zero-arity function
  that performs the async work. This is designed to work with LiveView's
  `start_async/3`.

  ## Example

      async_action :load_posts, [:filter] do
        posts = MyApp.Posts.list(filter)
        set_posts(state, posts)
      end

  In your LiveView:

      def handle_event("load", params, socket) do
        {:async, work_fn} = State.apply(socket.assigns.state, {:load_posts, params})
        {:noreply, start_async(socket, :load_posts, work_fn)}
      end

      def handle_async(:load_posts, {:ok, new_state}, socket) do
        {:noreply, assign(socket, :state, new_state)}
      end

  ## Options

  Pass options as the third argument before the do block:

      async_action :load_posts, [:filter], timeout: 30_000 do
        # ...
      end

  """
  defmacro async_action(name, args \\ [], opts_or_block)

  defmacro async_action(name, args, do: block) do
    async_action_impl(name, args, [], block)
  end

  defmacro async_action(name, args, opts) when is_list(opts) do
    {block, opts} = Keyword.pop(opts, :do)
    async_action_impl(name, args, opts, block)
  end

  defp async_action_impl(name, args, opts, block) do
    {args, guards} = extract_guards(args)
    {arg_names, arg_types} = extract_args_with_types(args)
    _timeout = Keyword.get(opts, :timeout, 30_000)

    quote do
      @live_schema_actions {unquote(name), unquote(arg_types), :async}

      unquote(generate_async_action_clause(name, arg_names, guards, block))
    end
  end

  # Extract guards from args (e.g., [:amount] when is_integer(amount))
  defp extract_guards({:when, _, [args, guards]}), do: {args, guards}
  defp extract_guards(args), do: {args, nil}

  # Extract just the names from the args list (for backwards compat)
  defp extract_arg_names(args) when is_list(args), do: args
  defp extract_arg_names(_), do: []

  # Extract args with types, supporting both formats:
  # - [:id, :name] -> [{:id, nil}, {:name, nil}]
  # - [id: :integer, name: :string] -> [{:id, :integer}, {:name, :string}]
  # Returns {arg_names, arg_types_list}
  defp extract_args_with_types(args) when is_list(args) do
    # Check if it's a keyword list (typed args) or plain list (untyped args)
    if Keyword.keyword?(args) and length(args) > 0 and is_atom(hd(Keyword.values(args))) do
      # Typed format: [id: :integer, name: :string]
      arg_names = Keyword.keys(args)
      arg_types = Enum.map(args, fn {name, type} -> {name, type} end)
      {arg_names, arg_types}
    else
      # Untyped format: [:id, :name]
      arg_names = extract_arg_names(args)
      arg_types = Enum.map(arg_names, fn name -> {name, nil} end)
      {arg_names, arg_types}
    end
  end

  defp extract_args_with_types(_), do: {[], []}

  # Generate the apply_action clause for a sync action
  defp generate_action_clause(name, arg_names, guards, block) do
    pattern = build_action_pattern(name, arg_names)

    body =
      quote do
        var!(state) = state
        unquote(bind_args(arg_names))
        unquote(block)
      end

    if guards do
      quote do
        defp apply_action(state, unquote(pattern)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp apply_action(state, unquote(pattern)) do
          unquote(body)
        end
      end
    end
  end

  # Generate the apply_action clause for an async action
  defp generate_async_action_clause(name, arg_names, guards, block) do
    pattern = build_action_pattern(name, arg_names)

    body =
      quote do
        current_state = state
        unquote(capture_args(arg_names))

        work_fn = fn ->
          var!(state) = current_state
          unquote(bind_captured_args(arg_names))
          unquote(block)
        end

        {:async, work_fn}
      end

    if guards do
      quote do
        defp apply_action(state, unquote(pattern)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp apply_action(state, unquote(pattern)) do
          unquote(body)
        end
      end
    end
  end

  # Build the action tuple pattern for matching
  defp build_action_pattern(name, []) do
    quote do: {unquote(name)}
  end

  defp build_action_pattern(name, arg_names) do
    arg_vars = Enum.map(arg_names, fn arg -> Macro.var(arg, nil) end)
    quote do: {unquote(name), unquote_splicing(arg_vars)}
  end

  # Bind args from the action tuple to local variables
  defp bind_args([]), do: nil

  defp bind_args(arg_names) do
    bindings =
      Enum.map(arg_names, fn arg ->
        var = Macro.var(arg, nil)

        quote do
          _ = unquote(var)
        end
      end)

    quote do: (unquote_splicing(bindings))
  end

  # Capture args for async action closure
  defp capture_args([]), do: nil

  defp capture_args(arg_names) do
    captures =
      Enum.map(arg_names, fn arg ->
        var = Macro.var(arg, nil)
        captured_var = Macro.var(:"captured_#{arg}", nil)

        quote do
          unquote(captured_var) = unquote(var)
        end
      end)

    quote do: (unquote_splicing(captures))
  end

  # Bind captured args inside async closure
  defp bind_captured_args([]), do: nil

  defp bind_captured_args(arg_names) do
    bindings =
      Enum.map(arg_names, fn arg ->
        var = Macro.var(arg, nil)
        captured_var = Macro.var(:"captured_#{arg}", nil)

        quote do
          unquote(var) = unquote(captured_var)
        end
      end)

    quote do: (unquote_splicing(bindings))
  end

  @doc """
  Defines a reaction - an action that returns a reply to the client.

  Reactions are used when you need to push data back to the client
  via `{:reply, payload, socket}`. The body must return a tuple of
  `{new_state, reply_payload}`.

  ## Examples

      # Get data and reply with it
      reaction :get_count do
        {state, %{count: state.count}}
      end

      # With arguments
      reaction :fetch_item, [id: :integer] do
        item = Enum.find(state.items, &(&1.id == id))
        {state, %{item: item}}
      end

      # Modify state and reply
      reaction :increment_and_get do
        new_state = set_count(state, state.count + 1)
        {new_state, %{count: new_state.count}}
      end

  In your LiveView (manual):

      def handle_event("get_count", _params, socket) do
        {:reply, payload, new_state} = State.apply(socket.assigns.state, {:get_count})
        {:reply, payload, assign(socket, :state, new_state)}
      end

  Or with `generate_events: true`, this is handled automatically.

  """
  defmacro reaction(name, args \\ [], do: block) do
    {args, guards} = extract_guards(args)
    {arg_names, arg_types} = extract_args_with_types(args)

    quote do
      @live_schema_actions {unquote(name), unquote(arg_types), :reply}

      unquote(generate_reaction_clause(name, arg_names, guards, block))
    end
  end

  # Generate the apply_action clause for a reaction
  defp generate_reaction_clause(name, arg_names, guards, block) do
    pattern = build_action_pattern(name, arg_names)

    body =
      quote do
        var!(state) = state
        unquote(bind_args(arg_names))
        {new_state, payload} = unquote(block)
        {:reply, payload, new_state}
      end

    if guards do
      quote do
        defp apply_action(state, unquote(pattern)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp apply_action(state, unquote(pattern)) do
          unquote(body)
        end
      end
    end
  end
end
