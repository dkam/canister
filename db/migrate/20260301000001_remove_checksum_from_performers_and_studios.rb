class RemoveChecksumFromPerformersAndStudios < ActiveRecord::Migration[8.1]
  def change
    remove_index :performers, :checksum if index_exists?(:performers, :checksum)
    remove_column :performers, :checksum

    remove_index :studios, :checksum if index_exists?(:studios, :checksum)
    remove_column :studios, :checksum
  end
end
