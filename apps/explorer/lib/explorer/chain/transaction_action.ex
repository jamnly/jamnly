defmodule Explorer.Chain.TransactionAction do
  @moduledoc "Models transaction action."

  use Explorer.Schema

  alias Explorer.Chain.{
    Hash,
    Transaction
  }

  @required_attrs ~w(hash protocol data type log_index)a
  @supported_protocols [:uniswap_v3, :opensea_v1_1, :wrapping, :approval, :zkbob, :aave_v3]

  @typedoc """
  * `hash` - transaction hash
  * `protocol` - name of the action protocol (see possible values for Enum of the db table field)
  * `data` - transaction action details (json formatted)
  * `type` - type of the action protocol (see possible values for Enum of the db table field)
  * `log_index` - index of the action for sorting (taken from log.index)
  """
  @primary_key false
  typed_schema "transaction_actions" do
    field(:protocol, Ecto.Enum, values: @supported_protocols, null: false)
    field(:data, :map, null: false)

    field(:type, Ecto.Enum,
      values: [
        :mint_nft,
        :mint,
        :burn,
        :collect,
        :swap,
        :sale,
        :cancel,
        :transfer,
        :wrap,
        :unwrap,
        :approve,
        :revoke,
        :withdraw,
        :deposit,
        :borrow,
        :supply,
        :repay,
        :flash_loan,
        :enable_collateral,
        :disable_collateral,
        :liquidation_call
      ],
      null: false
    )

    field(:log_index, :integer, primary_key: true, null: false)

    belongs_to(:transaction, Transaction,
      foreign_key: :hash,
      primary_key: true,
      references: :hash,
      type: Hash.Full,
      null: false
    )

    timestamps()
  end

  def changeset(%__MODULE__{} = tx_actions, attrs \\ %{}) do
    tx_actions
    |> cast(attrs, @required_attrs)
    |> validate_required(@required_attrs)
    |> foreign_key_constraint(:hash)
  end

  def supported_protocols do
    @supported_protocols
  end
end
