class CreatePost < ActiveRecord::Migration[6.1]
  def change
    create_table :posts do |t|
      t.string :author
      t.text :content
      t.timestamps null: false
    end
  end
end
