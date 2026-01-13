defmodule LiveSchema.PubSub do
  @moduledoc """
  PubSub integration for synchronizing state across LiveView processes.

  Provides helpers for broadcasting state changes and subscribing to updates.

  ## Usage

  Define synced fields in your schema:

      defmodule MyApp.PostsState do
        use LiveSchema

        @pubsub MyApp.PubSub
        @topic "posts"

        schema do
          field :posts, {:list, {:struct, Post}}, default: []

          sync_field :posts  # Broadcast changes to this field
        end

        reducer :add_post, [:post] do
          set_posts(state, [post | state.posts])
        end
      end

  In your LiveView:

      def mount(_params, _session, socket) do
        if connected?(socket) do
          LiveSchema.PubSub.subscribe(MyApp.PubSub, "posts")
        end

        {:ok, assign(socket, :state, PostsState.new())}
      end

      def handle_info({:live_schema_sync, :posts, posts}, socket) do
        {:noreply, update_state(socket, &PostsState.set_posts(&1, posts))}
      end

  ## Conflict Resolution

  When multiple processes update the same state, you can define
  a conflict resolution strategy:

      sync_field :posts, on_conflict: :last_write_wins
      sync_field :counter, on_conflict: &merge_counters/2

  """

  @doc """
  Subscribes to state sync updates for a topic.

  ## Examples

      LiveSchema.PubSub.subscribe(MyApp.PubSub, "posts")
      LiveSchema.PubSub.subscribe(MyApp.PubSub, "posts:\#{post_id}")

  """
  @spec subscribe(module(), String.t()) :: :ok | {:error, term()}
  def subscribe(pubsub, topic) do
    Phoenix.PubSub.subscribe(pubsub, "live_schema:#{topic}")
  end

  @doc """
  Unsubscribes from state sync updates.
  """
  @spec unsubscribe(module(), String.t()) :: :ok | {:error, term()}
  def unsubscribe(pubsub, topic) do
    Phoenix.PubSub.unsubscribe(pubsub, "live_schema:#{topic}")
  end

  @doc """
  Broadcasts a field change to all subscribers.

  This is typically called automatically by synced reducers,
  but can be called manually if needed.

  ## Examples

      LiveSchema.PubSub.broadcast(MyApp.PubSub, "posts", :posts, updated_posts)

  """
  @spec broadcast(module(), String.t(), atom(), any()) :: :ok | {:error, term()}
  def broadcast(pubsub, topic, field, value) do
    Phoenix.PubSub.broadcast(pubsub, "live_schema:#{topic}", {:live_schema_sync, field, value})
  end

  @doc """
  Broadcasts a field change to all subscribers except the sender.

  Useful when you want to sync to others but not back to yourself.

  ## Examples

      LiveSchema.PubSub.broadcast_from(self(), MyApp.PubSub, "posts", :posts, updated_posts)

  """
  @spec broadcast_from(pid(), module(), String.t(), atom(), any()) :: :ok | {:error, term()}
  def broadcast_from(from_pid, pubsub, topic, field, value) do
    Phoenix.PubSub.broadcast_from(
      pubsub,
      from_pid,
      "live_schema:#{topic}",
      {:live_schema_sync, field, value}
    )
  end

  @doc """
  Returns a sync topic for a specific resource.

  ## Examples

      topic = LiveSchema.PubSub.topic("posts", post.id)
      # => "posts:123"

  """
  @spec topic(String.t(), any()) :: String.t()
  def topic(base, id) do
    "#{base}:#{id}"
  end
end

defmodule LiveSchema.PubSub.SyncField do
  @moduledoc false

  # Internal module for handling sync_field macro

  defmacro sync_field(name, opts \\ []) do
    quote do
      @live_schema_sync_fields {unquote(name), unquote(opts)}
    end
  end
end
