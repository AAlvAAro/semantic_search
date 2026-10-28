# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_26_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "chunks", force: :cascade do |t|
    t.string "variant", null: false
    t.string "guide", null: false
    t.integer "position", null: false
    t.string "heading", default: "", null: false
    t.text "body", null: false
    t.vector "embedding", limit: 384
    t.string "content_hash"
    t.string "embedding_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["variant", "guide", "position"], name: "index_chunks_on_variant_and_guide_and_position", unique: true
  end
end
