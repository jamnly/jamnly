defmodule Explorer.Chain.MapCache do
  @moduledoc """
  Behaviour for a map-like cache of elements.

  A macro based on `ConCache` is provided as well, at its minimum it can be used as;
  ```
    use Explorer.Chain.MapCache,
      name: :name,
      keys: [:fst, :snd]
  ```
  Note: `keys` can also be set singularly with the option `key`, e.g.:
  ```
    use Explorer.Chain.MapCache,
      name: :cache,
      key: :fst,
      key: :snd
  ```
  Additionally all of the options accepted by `ConCache.start_link/1` can be
  provided as well. By default only `ttl_check_interval:` is set (to `false`).

  ## Named functions
  Apart from the functions defined in the behaviour, the macro will also create
  3 named function for each key, for instance for the key `:fst`:
  - `get_fst`
  - `set_fst`
  - `update_fst`
  These all work as their respective counterparts with the `t:key/0` parameter.

  ## Callbacks
  Apart from the `callback` that can be set as part of the `ConCache` options,
  two callbacks exist and can be overridden:

  `c:handle_update/3` will be called whenever an update is issued. It will receive
  the `t:key/0` that is going to be updated, the current `t:value/0` that is
  stored for said key and the new `t:value/0` to evaluate.
  This allows to select what value to keep and do additional processing.
  By default this just stores the new `t:value/0`.

  `c:handle_fallback/1` will be called whenever a get is performed and there is no
  stored value for the given `t:key/0` (or when the value is `nil`).
  It can return 2 different tuples:
  - `{:update, value}` that will cause the value to be returned and the `t:key/0`
    to be `c:update/2`d
  - `{:return, value}` that will cause the value to be returned but not stored
  This allows to define of a default value or perform some actions.
  By default it will simply `{:return, nil}`
  """

  @type key :: atom()

  @type value :: term()

  @doc """
  An atom that identifies this cache
  """
  @callback cache_name :: atom()

  @doc """
  List of `t:key/0`s that the cache contains
  """
  @callback cache_keys :: [key()]

  @doc """
  Gets everything in a map
  """
  @callback get_all :: map()

  @doc """
  Gets the stored `t:value/0` for a given `t:key/0`
  """
  @callback get(atom()) :: value()

  @doc """
  Stores the same `t:value/0` for every `t:key/0`
  """
  @callback set_all(value()) :: :ok

  @doc """
  Stores the given `t:value/0` for the given `t:key/0`
  """
  @callback set(key(), value()) :: :ok

  @doc """
  Updates every `t:key/0` with the given `t:value/0`
  """
  @callback update_all(value()) :: :ok

  @doc """
  Updates the given `t:key/0` (or every `t:key/0` in a list) using the given `t:value/0`
  """
  @callback update(key() | [key()], value()) :: :ok

  @doc """
  Gets called during an update for the given `t:key/0`
  """
  @callback handle_update(key(), value(), value()) :: {:ok, value()} | {:error, term()}

  @doc """
  Gets called when a `c:get/1` finds no `t:value/0`
  """
  @callback handle_fallback(key()) :: {:update, value()} | {:return, value()}

  # credo:disable-for-next-line /Complexity/
  defmacro __using__(opts) when is_list(opts) do
    # name is necessary
    name = Keyword.fetch!(opts, :name)
    keys = Keyword.get(opts, :keys) || Keyword.get_values(opts, :key)

    concache_params =
      opts
      |> Keyword.drop([:keys, :key])
      |> Keyword.put_new(:ttl_check_interval, false)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      alias Explorer.Chain.MapCache

      @behaviour MapCache

      @dialyzer {:nowarn_function, handle_fallback: 1}

      @impl MapCache
      def cache_name, do: unquote(name)

      @impl MapCache
      def cache_keys, do: unquote(keys)

      @impl MapCache
      def get_all do
        Map.new(cache_keys(), fn key -> {key, get(key)} end)
      end

      @impl MapCache
      def get(key) do
        case ConCache.get(cache_name(), key) do
          nil ->
            case handle_fallback(key) do
              {:update, new_value} ->
                update(key, new_value)
                new_value

              {:return, new_value} ->
                new_value
            end

          value ->
            value
        end
      end

      @impl MapCache
      def set_all(value) do
        Enum.each(cache_keys(), &set(&1, value))
      end

      @impl MapCache
      def set(key, value) do
        ConCache.put(cache_name(), key, value)
      end

      @impl MapCache
      def update_all(value), do: update(cache_keys(), value)

      @impl MapCache
      def update(keys, value) when is_list(keys) do
        Enum.each(keys, &update(&1, value))
      end

      @impl MapCache
      def update(key, value) do
        ConCache.update(cache_name(), key, fn old_val -> handle_update(key, old_val, value) end)
      end

      ### Autogenerated named functions

      unquote(Enum.map(keys, &named_functions(&1)))

      ### Overridable callback functions

      @impl MapCache
      def handle_update(_key, _old_value, new_value), do: {:ok, new_value}

      @impl MapCache
      def handle_fallback(_key), do: {:return, nil}

      defoverridable handle_update: 3, handle_fallback: 1

      ### Supervisor's child specification

      @doc """
      The child specification for a Supervisor. Note that all the `params`
      provided to this function will override the ones set by using the macro
      """
      def child_spec(params \\ []) do
        params = Keyword.merge(unquote(concache_params), params)

        Supervisor.child_spec({ConCache, params}, id: child_id())
      end

      def child_id, do: {ConCache, cache_name()}
    end
  end

  # sobelow_skip ["DOS"]
  defp named_functions(key) do
    quote do
      # sobelow_skip ["DOS"]
      def unquote(:"get_#{key}")(), do: get(unquote(key))

      # sobelow_skip ["DOS"]
      def unquote(:"set_#{key}")(value), do: set(unquote(key), value)

      # sobelow_skip ["DOS"]
      def unquote(:"update_#{key}")(value), do: update(unquote(key), value)
    end
  end
end
