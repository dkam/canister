class AddCredentialsToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_column :libraries, :username, :string
    add_column :libraries, :password, :string
  end
end
