defmodule Explorer.Chain.Cache.AddressSum do
  @moduledoc """
  Cache for address sum.
  """

  require Logger

  use Explorer.Chain.MapCache,
    name: :address_sum,
    key: :sum,
    key: :async_task,
    ttl_check_interval: Application.get_env(:explorer, __MODULE__)[:ttl_check_interval],
    global_ttl: :infinity,
    callback: &async_task_on_deletion(&1)

  alias Explorer.Chain.Cache.Helper
  alias Explorer.Etherscan

  defp handle_fallback(:sum) do
    # This will get the task PID if one exists and launch a new task if not
    # See next `handle_fallback` definition
    get_async_task()

    {:return, Decimal.new(0)}
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists
    # so a new one needs to be launched
    {:ok, task} =
      Task.start(fn ->
        try do
          result = Etherscan.fetch_sum_coin_total_supply()

          set_sum(%ConCache.Item{ttl: Helper.ttl(__MODULE__, "CACHE_ADDRESS_SUM_PERIOD"), value: result})
        rescue
          e ->
            Logger.debug([
              "Couldn't update address sum: ",
              Exception.format(:error, e, __STACKTRACE__)
            ])
        end

        set_async_task(nil)
      end)

    {:update, task}
  end

  # By setting this as a `callback` an async task will be started each time the
  # `sum` expires (unless there is one already running)
  defp async_task_on_deletion({:delete, _, :sum}), do: get_async_task()

  defp async_task_on_deletion(_data), do: nil
end
