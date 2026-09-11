defmodule Lotus.Test.Repo.Migrations.MigrateLotusV5 do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end
