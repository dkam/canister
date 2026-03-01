class CreatePerformers < ActiveRecord::Migration[8.1]
  def change
    create_table :performers, id: :uuid do |t|
      t.string :aliases
      t.date :birthdate
      t.string :career_length
      t.string :checksum
      t.string :country
      t.string :ethnicity
      t.string :eye_color
      t.string :fake_tits
      t.boolean :favorite, default: false, null: false
      t.string :height
      t.binary :image, limit: 2097152
      t.string :instagram
      t.string :measurements
      t.string :name
      t.string :piercings
      t.string :tattoos
      t.string :twitter
      t.string :url

      t.timestamps
    end

    add_index :performers, :checksum
    add_index :performers, :name
  end
end
