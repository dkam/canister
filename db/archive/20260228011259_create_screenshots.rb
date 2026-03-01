class CreateScreenshots < ActiveRecord::Migration[8.1]
  def change
    create_table :screenshots do |t|
      t.references :scene, null: false, foreign_key: true
      t.float :timecode

      t.timestamps
    end
  end
end
