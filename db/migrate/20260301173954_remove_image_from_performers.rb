class RemoveImageFromPerformers < ActiveRecord::Migration[8.1]
  def change
    remove_column :performers, :image, :binary
  end
end
