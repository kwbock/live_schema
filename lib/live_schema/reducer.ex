defmodule LiveSchema.Reducer do
  @moduledoc """
  Macros for defining reducer-based state transitions.

  Reducers provide an Elm-style pattern for state management where all
  state transitions are explicit and go through a central `apply/2` function.

  ## Basic Usage

      defmodule MyApp.State do
        use LiveSchema

        schema do
          field :count, :integer, default: 0
          field :posts, {:list, {:struct, Post}}, default: []
        end

        reducer :increment do
          set_count(state, state.count + 1)
        end

        reducer :select_post, [:id] do
          post = Enum.find(state.posts, &(&1.id == id))
          set_selected(state, post)
        end
      end

  ## With Guards

      reducer :increment, [:amount] when is_integer(amount) and amount > 0 do
        set_count(state, state.count + amount)
      end

  ## Async Reducers

  For operations that need to perform async work:

      async_reducer :load_posts, [:filter] do
        posts = MyApp.Posts.list(filter)
        set_posts(state, posts)
      end

  This generates a function that returns `{:async, fun}` for use with
  LiveView's `start_async/3`.

  """

  @doc """
  Defines a synchronous reducer.

  The reducer body has access to:
  - `state` - The current state struct
  - Any arguments specified in the args list

  ## Examples

      # No arguments
      reducer :reset do
        MyApp.State.new()
      end

      # With arguments
      reducer :set_filter, [:field, :value] do
        update_in(state.filter, &Map.put(&1, field, value))
      end

      # With guards
      reducer :add, [:n] when is_integer(n) and n > 0 do
        set_count(state, state.count + n)
      end

  """
  defmacro reducer(name, args \\ [], do: block) do
    {args, guards} = extract_guards(args)
    arg_names = extract_arg_names(args)

    quote do
      @live_schema_reducers {unquote(name), unquote(arg_names), :sync}

      unquote(generate_reducer_clause(name, arg_names, guards, block))
    end
  end

  @doc """
  Defines an asynchronous reducer.

  Async reducers return `{:async, fun}` where `fun` is a zero-arity function
  that performs the async work. This is designed to work with LiveView's
  `start_async/3`.

  ## Example

      async_reducer :load_posts, [:filter] do
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

      async_reducer :load_posts, [:filter], timeout: 30_000 do
        # ...
      end

  """
  defmacro async_reducer(name, args \\ [], opts_or_block)

  defmacro async_reducer(name, args, do: block) do
    async_reducer_impl(name, args, [], block)
  end

  defmacro async_reducer(name, args, opts) when is_list(opts) do
    {block, opts} = Keyword.pop(opts, :do)
    async_reducer_impl(name, args, opts, block)
  end

  defp async_reducer_impl(name, args, opts, block) do
    {args, guards} = extract_guards(args)
    arg_names = extract_arg_names(args)
    _timeout = Keyword.get(opts, :timeout, 30_000)

    quote do
      @live_schema_reducers {unquote(name), unquote(arg_names), :async}

      unquote(generate_async_reducer_clause(name, arg_names, guards, block))
    end
  end

  # Extract guards from args (e.g., [:amount] when is_integer(amount))
  defp extract_guards({:when, _, [args, guards]}), do: {args, guards}
  defp extract_guards(args), do: {args, nil}

  # Extract just the names from the args list
  defp extract_arg_names(args) when is_list(args), do: args
  defp extract_arg_names(_), do: []

  # Generate the apply_reducer clause for a sync reducer
  defp generate_reducer_clause(name, arg_names, guards, block) do
    pattern = build_action_pattern(name, arg_names)

    body =
      quote do
        var!(state) = state
        unquote(bind_args(arg_names))
        unquote(block)
      end

    if guards do
      quote do
        defp apply_reducer(state, unquote(pattern)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp apply_reducer(state, unquote(pattern)) do
          unquote(body)
        end
      end
    end
  end

  # Generate the apply_reducer clause for an async reducer
  defp generate_async_reducer_clause(name, arg_names, guards, block) do
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
        defp apply_reducer(state, unquote(pattern)) when unquote(guards) do
          unquote(body)
        end
      end
    else
      quote do
        defp apply_reducer(state, unquote(pattern)) do
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

  # Capture args for async reducer closure
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
end
