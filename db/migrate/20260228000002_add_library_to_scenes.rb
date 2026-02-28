class AddLibraryToScenes < ActiveRecord::Migration[8.1]
  def change
    add_reference :scenes, :library, foreign_key: true
  end
end
