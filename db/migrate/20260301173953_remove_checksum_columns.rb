class RemoveChecksumColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :videos, :checksum, :string
    remove_column :galleries, :checksum, :string
  end
end
