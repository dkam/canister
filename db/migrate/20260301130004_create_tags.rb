class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags, id: :uuid do |t|
      t.string :name

      t.timestamps
    end

    add_index :tags, :name
  end
end
