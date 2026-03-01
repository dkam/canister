# UUID in Rails

Rails 8.1's built-in UUIDv7 support which eliminates the pain. Here's the magic:

## In Migrations
    Just use id: :uuid:
    create_table :accounts, id: :uuid do |t|
      # Rails automatically creates a binary(16) column and generates UUIDs
    end
## In Models
    No configuration needed! Rails automatically detects UUID primary keys:
    class Account < ApplicationRecord
      # No primary_key declaration required - Rails figures it out
    end
    The Secret Sauce (config/initializers/uuid_primary_keys.rb)

## DB Support
    Custom adapters make binary(16) (MySQL) and blob(16) (SQLite) columns appear as :uuid type to Rails:
    - MysqlUuidAdapter - maps binary(16) → :uuid
    - SqliteUuidAdapter - maps blob(16) → :uuid
    - SchemaDumperUuidType - dumps schema as id: :uuid instead of raw SQL
    - Auto-generates UUIDs via ActiveRecord::Type::Uuid.generate

## How It Works
    1. Database: Stores UUIDs as 16-byte binary columns (efficient)
    2. Rails: Exposes them as 25-char base36 strings like "01jcqzx8h0000000000000000" (readable)
    3. Generation: Automatic via ActiveRecord::Type::Uuid.generate (UUIDv7 format)
    No more string columns, no more primary_key: declarations, no more pain!
