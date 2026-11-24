defmodule Hailstorm.TestUser do
  use Ecto.Schema
  alias Hailstorm.Repo
  alias Ecto.Changeset
  import Ecto.Query

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          email: String.t(),
          access_token: String.t(),
          refresh_token: String.t()
        }

  @primary_key {:id, :integer, autogenerate: false}
  schema "test_user" do
    # field :id, :integer
    field(:name, :string)
    field(:email, :string)
    field(:access_token, :string)
    field(:refresh_token, :string)
  end

  def all() do
    from(u in __MODULE__, order_by: [asc: u.name])
    |> Repo.all()
  end

  def update_token(user, access, refresh) do
    Changeset.change(user, access_token: access, refresh_token: refresh)
    |> Repo.update()
  end

  def get(id) do
    Repo.get!(__MODULE__, id)
  end
end
