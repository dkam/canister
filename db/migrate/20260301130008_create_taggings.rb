class CreateTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :taggings, id: :uuid do |t|
      t.references :tag, type: :uuid, foreign_key: true
      t.string :taggable_id    # polymorphic: UUID stored as base36 string
      t.string :taggable_type

      t.timestamps
    end

    add_index :taggings, [ :taggable_type, :taggable_id ]
  end
end
