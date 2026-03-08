class RemoveChecksumFromPerformersAndStudios < ActiveRecord::Migration[8.1]
  def change
    remove_index :people, :checksum if index_exists?(:people, :checksum)
    remove_column :people, :checksum

    remove_index :studios, :checksum if index_exists?(:studios, :checksum)
    remove_column :studios, :checksum
  end
end
