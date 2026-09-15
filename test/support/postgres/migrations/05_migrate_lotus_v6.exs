defmodule Lotus.Test.Repo.Migrations.MigrateLotusV6 do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end
