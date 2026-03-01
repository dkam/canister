class RemoveImageFromStudios < ActiveRecord::Migration[8.1]
  def change
    remove_column :studios, :image, :binary
  end
end
