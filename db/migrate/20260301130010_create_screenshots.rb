class CreateScreenshots < ActiveRecord::Migration[8.1]
  def change
    create_table :screenshots, id: :uuid do |t|
      t.references :scene, type: :uuid, null: false, foreign_key: true
      t.float :timecode

      t.timestamps
    end
  end
end
