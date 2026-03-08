class RemoveImageFromPerformers < ActiveRecord::Migration[8.1]
  def change
    remove_column :people, :image, :binary
  end
end
