class CreateStudios < ActiveRecord::Migration[8.1]
  def change
    create_table :studios, id: :uuid do |t|
      t.string :checksum
      t.binary :image, limit: 1048576
      t.string :name
      t.string :url

      t.timestamps
    end

    add_index :studios, :checksum
    add_index :studios, :name
  end
end
