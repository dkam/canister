class CreateScrapedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :scraped_items, id: :uuid do |t|
      t.date :date
      t.string :description
      t.integer :episode
      t.string :gallery_filename
      t.string :gallery_url
      t.string :models
      t.string :rating
      t.references :studio, type: :uuid, null: false, foreign_key: true
      t.string :tags
      t.string :title
      t.string :url
      t.string :video_filename
      t.string :video_url

      t.timestamps
    end
  end
end
