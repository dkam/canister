class CreateGalleries < ActiveRecord::Migration[8.1]
  def change
    create_table :galleries, id: :uuid do |t|
      t.string :checksum
      t.string :ownable_id    # polymorphic: UUID stored as base36 string
      t.string :ownable_type
      t.string :path
      t.string :title

      t.timestamps
    end

    add_index :galleries, [ :ownable_type, :ownable_id ]
  end
end
