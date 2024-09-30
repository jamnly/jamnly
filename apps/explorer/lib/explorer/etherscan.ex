defmodule Explorer.Etherscan do
  @moduledoc """
  The etherscan context.
  """

  import Ecto.Query,
    only: [from: 2, where: 3, union: 2, subquery: 1, order_by: 3, limit: 2, offset: 2, preload: 3]

  import Explorer.Chain.SmartContract, only: [burn_address_hash_string: 0]

  alias Explorer.Etherscan.Logs
  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Address.{CurrentTokenBalance, TokenBalance}
  alias Explorer.Chain.{Address, Block, DenormalizationHelper, Hash, InternalTransaction, TokenTransfer, Transaction}
  alias Explorer.Chain.Transaction.History.TransactionStats

  @default_options %{
    order_by_direction: :desc,
    page_number: 1,
    page_size: 10_000,
    startblock: nil,
    endblock: nil,
    start_timestamp: nil,
    end_timestamp: nil
  }

  @doc """
  Returns the maximum allowed page size number.

  """
  @spec page_size_max :: pos_integer()
  def page_size_max do
    @default_options.page_size
  end

  @doc """
  Gets a list of transactions for a given `t:Explorer.Chain.Hash.Address.t/0`.

  If `filter_by: "to"` is given as an option, address matching is only done
  against the `to_address_hash` column. If not, `to_address_hash`,
  `from_address_hash`, and `created_contract_address_hash` are all considered.

  """
  @spec list_transactions(Hash.Address.t()) :: [map()]
  def list_transactions(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash,
        options \\ @default_options
      ) do
    case Chain.max_consensus_block_number() do
      {:ok, max_block_number} ->
        merged_options = Map.merge(@default_options, options)
        list_transactions(address_hash, max_block_number, merged_options)

      _ ->
        []
    end
  end

  @doc """
  Gets a list of pending transactions for a given `t:Explorer.Chain.Hash.Address.t/0`.

  If `filter_by: `to_address_hash`,
  `from_address_hash`, and `created_contract_address_hash`.

  """
  @spec list_pending_transactions(Hash.Address.t()) :: [map()]
  def list_pending_transactions(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash,
        options \\ @default_options
      ) do
    merged_options = Map.merge(@default_options, options)
    list_pending_transactions_query(address_hash, merged_options)
  end

  @internal_transaction_fields ~w(
    from_address_hash
    to_address_hash
    transaction_hash
    index
    value
    created_contract_address_hash
    input
    type
    call_type
    gas
    gas_used
    error
  )a

  @doc """
  Gets a list of internal transactions for a given transaction hash
  (`t:Explorer.Chain.Hash.Full.t/0`).

  Note that this function relies on `Explorer.Chain` to exclude/include
  internal transactions as follows:

    * exclude internal transactions of type call with no siblings in the
      transaction
    * include internal transactions of type create, reward, or selfdestruct
      even when they are alone in the parent transaction

  """
  @spec list_internal_transactions(Hash.Full.t()) :: [map()]
  def list_internal_transactions(%Hash{byte_count: unquote(Hash.Full.byte_count())} = transaction_hash) do
    query =
      if DenormalizationHelper.transactions_denormalization_finished?() do
        from(
          it in InternalTransaction,
          inner_join: transaction in assoc(it, :transaction),
          where: not is_nil(transaction.block_hash),
          where: it.transaction_hash == ^transaction_hash,
          limit: 10_000,
          select:
            merge(map(it, ^@internal_transaction_fields), %{
              block_timestamp: transaction.block_timestamp,
              block_number: transaction.block_number
            })
        )
      else
        from(
          it in InternalTransaction,
          inner_join: t in assoc(it, :transaction),
          inner_join: b in assoc(t, :block),
          where: it.transaction_hash == ^transaction_hash,
          limit: 10_000,
          select:
            merge(map(it, ^@internal_transaction_fields), %{
              block_timestamp: b.timestamp,
              block_number: b.number
            })
        )
      end

    query
    |> InternalTransaction.where_transaction_has_multiple_internal_transactions()
    |> InternalTransaction.where_is_different_from_parent_transaction()
    |> InternalTransaction.where_nonpending_block()
    |> Repo.replica().all()
  end

  @doc """
  Gets a list of internal transactions for a given address hash
  (`t:Explorer.Chain.Hash.Address.t/0`).

  Note that this function relies on `Explorer.Chain` to exclude/include
  internal transactions as follows:

    * exclude internal transactions of type call with no siblings in the
      transaction
    * include internal transactions of type create, reward, or selfdestruct
      even when they are alone in the parent transaction

  """
  @spec list_internal_transactions(Hash.Address.t(), map()) :: [map()]
  def list_internal_transactions(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash,
        raw_options \\ %{}
      ) do
    options = Map.merge(@default_options, raw_options)

    direction =
      case options do
        %{filter_by: "to"} -> :to
        %{filter_by: "from"} -> :from
        _ -> nil
      end

    consensus_blocks =
      from(
        block in Block,
        where: block.consensus == true
      )

    if direction == nil do
      query =
        from(
          it in InternalTransaction,
          inner_join: block in subquery(consensus_blocks),
          on: it.block_number == block.number,
          order_by: [
            {^options.order_by_direction, it.block_number},
            {:desc, it.transaction_index},
            {:desc, it.index}
          ],
          limit: ^options.page_size,
          offset: ^offset(options),
          select:
            merge(map(it, ^@internal_transaction_fields), %{
              block_timestamp: block.timestamp,
              block_number: block.number
            })
        )

      query_to_address_hash_wrapped =
        query
        |> InternalTransaction.where_address_fields_match(address_hash, :to_address_hash)
        |> InternalTransaction.where_is_different_from_parent_transaction()
        |> where_start_block_match(options)
        |> where_end_block_match(options)
        |> Chain.wrapped_union_subquery()

      query_from_address_hash_wrapped =
        query
        |> InternalTransaction.where_address_fields_match(address_hash, :from_address_hash)
        |> InternalTransaction.where_is_different_from_parent_transaction()
        |> where_start_block_match(options)
        |> where_end_block_match(options)
        |> Chain.wrapped_union_subquery()

      query_created_contract_address_hash_wrapped =
        query
        |> InternalTransaction.where_address_fields_match(address_hash, :created_contract_address_hash)
        |> InternalTransaction.where_is_different_from_parent_transaction()
        |> where_start_block_match(options)
        |> where_end_block_match(options)
        |> Chain.wrapped_union_subquery()

      query_to_address_hash_wrapped
      |> union(^query_from_address_hash_wrapped)
      |> union(^query_created_contract_address_hash_wrapped)
      |> Chain.wrapped_union_subquery()
      |> order_by(
        [q],
        [
          {^options.order_by_direction, q.block_number},
          desc: q.index
        ]
      )
      |> Repo.replica().all()
    else
      query =
        if DenormalizationHelper.transactions_denormalization_finished?() do
          from(
            it in InternalTransaction,
            inner_join: transaction in assoc(it, :transaction),
            where: not is_nil(transaction.block_hash),
            order_by: [{^options.order_by_direction, transaction.block_number}],
            limit: ^options.page_size,
            offset: ^offset(options),
            select:
              merge(map(it, ^@internal_transaction_fields), %{
                block_timestamp: transaction.block_timestamp,
                block_number: transaction.block_number
              })
          )
        else
          from(
            it in InternalTransaction,
            inner_join: t in assoc(it, :transaction),
            inner_join: b in assoc(t, :block),
            order_by: [{^options.order_by_direction, t.block_number}],
            limit: ^options.page_size,
            offset: ^offset(options),
            select:
              merge(map(it, ^@internal_transaction_fields), %{
                block_timestamp: b.timestamp,
                block_number: b.number
              })
          )
        end

      query
      |> InternalTransaction.where_transaction_has_multiple_internal_transactions()
      |> InternalTransaction.where_address_fields_match(address_hash, direction)
      |> InternalTransaction.where_is_different_from_parent_transaction()
      |> where_start_block_match(options)
      |> where_end_block_match(options)
      |> InternalTransaction.where_nonpending_block()
      |> Repo.replica().all()
    end
  end

  @doc """
  Gets a list of token transfers for a given `t:Explorer.Chain.Hash.Address.t/0`.

  """
  @spec list_token_transfers(Hash.Address.t(), Hash.Address.t() | nil, map()) :: [map()]
  def list_token_transfers(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash,
        contract_address_hash,
        options \\ @default_options
      ) do
    case Chain.max_consensus_block_number() do
      {:ok, block_height} ->
        merged_options = Map.merge(@default_options, options)
        list_token_transfers(address_hash, contract_address_hash, block_height, merged_options)

      _ ->
        []
    end
  end

  @doc """
    Gets a list of ERC-721 token transfers for a given address_hash. If contract_address_hash is not nil, transfers will be filtered by contract.
  """
  @spec list_nft_transfers(Hash.Address.t(), Hash.Address.t() | nil, map()) :: [TokenTransfer.t()]
  def list_nft_transfers(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash,
        contract_address_hash,
        options \\ @default_options
      ) do
    options
    |> base_nft_transfers_query(contract_address_hash)
    |> where([tt], tt.from_address_hash == ^address_hash or tt.to_address_hash == ^address_hash)
    |> Repo.replica().all()
  end

  @doc """
    Gets a list of ERC-721 token transfers for a given token contract_address_hash.
  """
  @spec list_nft_transfers_by_token(Hash.Address.t(), map()) :: [TokenTransfer.t()]
  def list_nft_transfers_by_token(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = contract_address_hash,
        options \\ @default_options
      ) do
    options
    |> base_nft_transfers_query(contract_address_hash)
    |> Repo.replica().all()
  end

  defp base_nft_transfers_query(options, contract_address_hash) do
    options = Map.merge(@default_options, options)

    TokenTransfer.erc_721_token_transfers_query()
    |> where_contract_address_match(contract_address_hash)
    |> order_by([tt], [
      {^options.order_by_direction, tt.block_number},
      {^options.order_by_direction, tt.log_index}
    ])
    |> where_start_block_match_tt(options)
    |> where_end_block_match_tt(options)
    |> limit(^options.page_size)
    |> offset(^offset(options))
    |> preload([block: block], [{:block, block}, :transaction])
  end

  @doc """
  Gets a list of blocks mined by `t:Explorer.Chain.Hash.Address.t/0`.

  For each block it returns the block's number, timestamp, and reward.

  The block reward is the sum of the following:

  * Sum of the transaction fees (gas_used * gas_price) for the block
  * A static reward for miner (this value may change during the life of the chain)
  * The reward for uncle blocks (1/32 * static_reward * number_of_uncles)

  *NOTE*

  Uncles are not currently accounted for.

  """
  @spec list_blocks(Hash.Address.t()) :: [map()]
  def list_blocks(%Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash, options \\ %{}) do
    merged_options = Map.merge(@default_options, options)

    query =
      from(
        block in Block,
        where: block.miner_hash == ^address_hash,
        order_by: [desc: block.number],
        limit: ^merged_options.page_size,
        offset: ^offset(merged_options),
        select: %{
          number: block.number,
          timestamp: block.timestamp
        }
      )

    Repo.replica().all(query)
  end

  @doc """
  Gets the token balance for a given contract address hash and address hash.

  """
  @spec get_token_balance(Hash.Address.t(), Hash.Address.t()) :: TokenBalance.t() | nil
  def get_token_balance(
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = contract_address_hash,
        %Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash
      ) do
    query =
      from(
        ctb in CurrentTokenBalance,
        where: ctb.token_contract_address_hash == ^contract_address_hash,
        where: ctb.address_hash == ^address_hash,
        limit: 1,
        select: ctb
      )

    Repo.replica().one(query)
  end

  @doc """
  Gets a list of tokens owned by the given address hash.

  """
  @spec list_tokens(Hash.Address.t()) :: map() | []
  def list_tokens(%Hash{byte_count: unquote(Hash.Address.byte_count())} = address_hash) do
    query =
      from(
        ctb in CurrentTokenBalance,
        inner_join: t in assoc(ctb, :token),
        where: ctb.address_hash == ^address_hash,
        where: ctb.value > 0,
        select: %{
          balance: ctb.value,
          contract_address_hash: ctb.token_contract_address_hash,
          name: t.name,
          decimals: t.decimals,
          symbol: t.symbol,
          type: t.type,
          id: ctb.token_id
        }
      )

    Repo.replica().all(query)
  end

  @transaction_fields ~w(
    block_hash
    block_number
    block_consensus
    block_timestamp
    created_contract_address_hash
    cumulative_gas_used
    from_address_hash
    gas
    gas_price
    gas_used
    hash
    index
    input
    nonce
    status
    to_address_hash
    value
    revert_reason
  )a

  @pending_transaction_fields ~w(
    created_contract_address_hash
    cumulative_gas_used
    from_address_hash
    gas
    gas_price
    gas_used
    hash
    index
    input
    nonce
    to_address_hash
    value
    inserted_at
  )a

  defp list_pending_transactions_query(address_hash, options) do
    query =
      from(
        t in Transaction,
        limit: ^options.page_size,
        offset: ^offset(options),
        select: map(t, ^@pending_transaction_fields)
      )

    query
    |> where_address_match(address_hash, options)
    |> Chain.pending_transactions_query()
    |> order_by([transaction], desc: transaction.inserted_at, desc: transaction.hash)
    |> Repo.replica().all()
  end

  defp list_transactions(address_hash, max_block_number, options) do
    query =
      if DenormalizationHelper.transactions_denormalization_finished?() do
        from(
          t in Transaction,
          where: not is_nil(t.block_hash),
          where: t.block_consensus == true,
          order_by: [{^options.order_by_direction, t.block_number}],
          limit: ^options.page_size,
          offset: ^offset(options),
          select:
            merge(map(t, ^@transaction_fields), %{
              confirmations: fragment("? - ?", ^max_block_number, t.block_number)
            })
        )
      else
        from(
          t in Transaction,
          inner_join: b in assoc(t, :block),
          where: b.consensus == true,
          order_by: [{^options.order_by_direction, t.block_number}],
          limit: ^options.page_size,
          offset: ^offset(options),
          select:
            merge(map(t, ^@transaction_fields), %{
              block_timestamp: b.timestamp,
              confirmations: fragment("? - ?", ^max_block_number, t.block_number)
            })
        )
      end

    query
    |> where_address_match(address_hash, options)
    |> where_start_transaction_block_match(options)
    |> where_end_transaction_block_match(options)
    |> where_start_timestamp_match(options)
    |> where_end_timestamp_match(options)
    |> Repo.replica().all()
  end

  defp where_address_match(query, address_hash, %{filter_by: "to"}) do
    where(query, [t], t.to_address_hash == ^address_hash)
  end

  defp where_address_match(query, address_hash, %{filter_by: "from"}) do
    where(query, [t], t.from_address_hash == ^address_hash)
  end

  defp where_address_match(query, address_hash, _) do
    where(
      query,
      [t],
      t.to_address_hash == ^address_hash or t.from_address_hash == ^address_hash or
        t.created_contract_address_hash == ^address_hash
    )
  end

  @token_transfer_fields ~w(
    block_number
    block_hash
    block_consensus
    token_contract_address_hash
    transaction_hash
    from_address_hash
    to_address_hash
    amount
    amounts
  )a

  defp list_token_transfers(address_hash, contract_address_hash, block_height, options) do
    tt_query =
      from(
        tt in TokenTransfer,
        inner_join: tkn in assoc(tt, :token),
        where: tt.from_address_hash == ^address_hash,
        or_where: tt.to_address_hash == ^address_hash,
        order_by: [{^options.order_by_direction, tt.block_number}, {^options.order_by_direction, tt.log_index}],
        limit: ^options.page_size,
        offset: ^offset(options),
        select:
          merge(map(tt, ^@token_transfer_fields), %{
            token_ids: tt.token_ids,
            token_name: tkn.name,
            token_symbol: tkn.symbol,
            token_decimals: tkn.decimals,
            token_type: tkn.type,
            token_log_index: tt.log_index
          })
      )

    tt_specific_token_query =
      tt_query
      |> where_start_block_match_tt(options)
      |> where_end_block_match_tt(options)
      |> where_contract_address_match(contract_address_hash)

    wrapped_query =
      if DenormalizationHelper.transactions_denormalization_finished?() do
        from(
          tt in subquery(tt_specific_token_query),
          inner_join: t in Transaction,
          on:
            tt.transaction_hash == t.hash and tt.block_number == t.block_number and tt.block_hash == t.block_hash and
              t.block_consensus == true,
          order_by: [{^options.order_by_direction, tt.block_number}, {^options.order_by_direction, tt.token_log_index}],
          select: %{
            token_contract_address_hash: tt.token_contract_address_hash,
            transaction_hash: tt.transaction_hash,
            from_address_hash: tt.from_address_hash,
            to_address_hash: tt.to_address_hash,
            amount: tt.amount,
            amounts: tt.amounts,
            transaction_nonce: t.nonce,
            transaction_index: t.index,
            transaction_gas: t.gas,
            transaction_gas_price: t.gas_price,
            transaction_gas_used: t.gas_used,
            transaction_cumulative_gas_used: t.cumulative_gas_used,
            transaction_input: t.input,
            block_hash: t.block_hash,
            block_number: t.block_number,
            block_timestamp: t.block_timestamp,
            confirmations: fragment("? - ?", ^block_height, t.block_number),
            token_ids: tt.token_ids,
            token_name: tt.token_name,
            token_symbol: tt.token_symbol,
            token_decimals: tt.token_decimals,
            token_type: tt.token_type,
            token_log_index: tt.token_log_index
          }
        )
      else
        from(
          tt in subquery(tt_specific_token_query),
          inner_join: t in Transaction,
          on: tt.transaction_hash == t.hash and tt.block_number == t.block_number and tt.block_hash == t.block_hash,
          inner_join: b in assoc(t, :block),
          where: b.consensus == true,
          order_by: [{^options.order_by_direction, tt.block_number}, {^options.order_by_direction, tt.token_log_index}],
          select: %{
            token_contract_address_hash: tt.token_contract_address_hash,
            transaction_hash: tt.transaction_hash,
            from_address_hash: tt.from_address_hash,
            to_address_hash: tt.to_address_hash,
            amount: tt.amount,
            amounts: tt.amounts,
            transaction_nonce: t.nonce,
            transaction_index: t.index,
            transaction_gas: t.gas,
            transaction_gas_price: t.gas_price,
            transaction_gas_used: t.gas_used,
            transaction_cumulative_gas_used: t.cumulative_gas_used,
            transaction_input: t.input,
            block_hash: b.hash,
            block_number: b.number,
            block_timestamp: b.timestamp,
            confirmations: fragment("? - ?", ^block_height, t.block_number),
            token_ids: tt.token_ids,
            token_name: tt.token_name,
            token_symbol: tt.token_symbol,
            token_decimals: tt.token_decimals,
            token_type: tt.token_type,
            token_log_index: tt.token_log_index
          }
        )
      end

    wrapped_query
    |> Repo.replica().all()
  end

  defp where_start_block_match(query, %{startblock: nil}), do: query

  defp where_start_block_match(query, %{startblock: start_block}) do
    where(query, [..., block], block.number >= ^start_block)
  end

  defp where_end_block_match(query, %{endblock: nil}), do: query

  defp where_end_block_match(query, %{endblock: end_block}) do
    where(query, [..., block], block.number <= ^end_block)
  end

  defp where_start_transaction_block_match(query, %{startblock: nil}), do: query

  defp where_start_transaction_block_match(query, %{startblock: start_block} = params) do
    if DenormalizationHelper.transactions_denormalization_finished?() do
      where(query, [transaction], transaction.block_number >= ^start_block)
    else
      where_start_block_match(query, params)
    end
  end

  defp where_end_transaction_block_match(query, %{endblock: nil}), do: query

  defp where_end_transaction_block_match(query, %{endblock: end_block} = params) do
    if DenormalizationHelper.transactions_denormalization_finished?() do
      where(query, [transaction], transaction.block_number <= ^end_block)
    else
      where_end_block_match(query, params)
    end
  end

  defp where_start_block_match_tt(query, %{startblock: nil}), do: query

  defp where_start_block_match_tt(query, %{startblock: start_block}) do
    where(query, [tt], tt.block_number >= ^start_block)
  end

  defp where_end_block_match_tt(query, %{endblock: nil}), do: query

  defp where_end_block_match_tt(query, %{endblock: end_block}) do
    where(query, [tt], tt.block_number <= ^end_block)
  end

  defp where_start_timestamp_match(query, %{start_timestamp: nil}), do: query

  defp where_start_timestamp_match(query, %{start_timestamp: start_timestamp}) do
    if DenormalizationHelper.transactions_denormalization_finished?() do
      where(query, [transaction], ^start_timestamp <= transaction.block_timestamp)
    else
      where(query, [..., block], ^start_timestamp <= block.timestamp)
    end
  end

  defp where_end_timestamp_match(query, %{end_timestamp: nil}), do: query

  defp where_end_timestamp_match(query, %{end_timestamp: end_timestamp}) do
    if DenormalizationHelper.transactions_denormalization_finished?() do
      where(query, [transaction], transaction.block_timestamp <= ^end_timestamp)
    else
      where(query, [..., block], block.timestamp <= ^end_timestamp)
    end
  end

  defp where_contract_address_match(query, nil), do: query

  defp where_contract_address_match(query, contract_address_hash) do
    where(query, [tt], tt.token_contract_address_hash == ^contract_address_hash)
  end

  defp offset(options), do: (options.page_number - 1) * options.page_size

  @doc """
  Gets a list of logs that meet the criteria in a given filter map.

  Required filter parameters:

  * `from_block`
  * `to_block`
  * `address_hash` and/or `{x}_topic`
  * When multiple `{x}_topic` params are provided, then the corresponding
  `topic{x}_{x}_opr` param is required. For example, if "first_topic" and
  "second_topic" are provided, then "topic0_1_opr" is required.

  Supported `{x}_topic`s:

  * first_topic
  * second_topic
  * third_topic
  * fourth_topic

  Supported `topic{x}_{x}_opr`s:

  * topic0_1_opr
  * topic0_2_opr
  * topic0_3_opr
  * topic1_2_opr
  * topic1_3_opr
  * topic2_3_opr

  """
  @spec list_logs(map()) :: [map()]
  def list_logs(filter), do: Logs.list_logs(filter)

  @spec fetch_sum_coin_total_supply() :: non_neg_integer
  def fetch_sum_coin_total_supply do
    query =
      from(
        a0 in Address,
        select: fragment("SUM(a0.fetched_coin_balance)"),
        where: a0.fetched_coin_balance > ^0
      )

    Repo.replica().one!(query, timeout: :infinity) || 0
  end

  @spec fetch_sum_coin_total_supply_minus_burnt() :: non_neg_integer
  def fetch_sum_coin_total_supply_minus_burnt do
    {:ok, burn_address_hash} = Chain.string_to_address_hash(burn_address_hash_string())

    query =
      from(
        a0 in Address,
        select: fragment("SUM(a0.fetched_coin_balance)"),
        where: a0.hash != ^burn_address_hash,
        where: a0.fetched_coin_balance > ^0
      )

    Repo.replica().one!(query, timeout: :infinity) || 0
  end

  @doc """
  It is used by `totalfees` API endpoint of `stats` module for retrieving of total fee per day
  """
  @spec get_total_fees_per_day(String.t()) :: {:ok, non_neg_integer() | nil} | {:error, String.t()}
  def get_total_fees_per_day(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        query =
          from(
            tx_stats in TransactionStats,
            where: tx_stats.date == ^date,
            select: tx_stats.total_fee
          )

        total_fees = Repo.replica().one(query)
        {:ok, total_fees}

      _ ->
        {:error, "An incorrect input date provided. It should be in ISO 8601 format (yyyy-mm-dd)."}
    end
  end
end
