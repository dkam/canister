module SqliteSearch
  extend ActiveSupport::Concern

  private def update_search_index
    return unless self.class.auto_update_search_index?

    conn = self.class.connection
    primary_key = self.class.primary_key
    table_name = conn.quote_table_name("fts_#{self.class.table_name}")
    foreign_key = conn.quote_column_name(self.class.to_s.foreign_key)
    id_value = conn.quote(attributes[primary_key])

    # Build column names and values with proper quoting
    columns = self.class.search_scope_attrs.map { |attr| conn.quote_column_name(attr) }
    values = self.class.search_scope_attrs.map { |attr| conn.quote(send(attr) || "") }

    # Delete existing entry
    sql_delete = "DELETE FROM #{table_name} WHERE #{foreign_key} = #{id_value}"
    conn.execute(sql_delete)

    # Insert new entry
    all_columns = (columns + [foreign_key]).join(", ")
    all_values = (values + [id_value]).join(", ")

    sql_insert = "INSERT INTO #{table_name}(#{all_columns}) VALUES (#{all_values})"
    conn.execute(sql_insert)
  end

  private def delete_search_index
    return unless self.class.auto_update_search_index?

    conn = self.class.connection
    primary_key = self.class.primary_key
    table_name = conn.quote_table_name("fts_#{self.class.table_name}")
    foreign_key = conn.quote_column_name(self.class.to_s.foreign_key)
    id_value = conn.quote(attributes[primary_key])

    sql_delete = "DELETE FROM #{table_name} WHERE #{foreign_key} = #{id_value}"
    conn.execute(sql_delete)
  end

  included do
    class_attribute :auto_update_search_index, default: true

    after_save_commit :update_search_index
    after_destroy_commit :delete_search_index

    scope :full_search, ->(query) {
      return none if query.blank?

      conn = connection
      fts_table = conn.quote_table_name("fts_#{table_name}")
      foreign_key_col = conn.quote_column_name(klass.to_s.foreign_key)

      # For FTS5, we need to remove/replace problematic characters
      # Remove characters that could cause FTS5 syntax errors (including periods which break token syntax)
      fts_query = query.gsub(/['";<>=.]/, " ").tr("-", " ")

      # Split into words and filter out FTS5 reserved words
      # FTS5 reserved words: AND, OR, NOT, NEAR
      reserved_words = %w[AND OR NOT NEAR]
      words = fts_query.split(/\s+/).reject(&:blank?).reject { |w| reserved_words.include?(w.upcase) }
      return none if words.empty?

      # Add prefix matching with * wildcard for partial word matches
      # Only add * if word doesn't already end with it or contain special FTS5 characters
      fts_query = words.map { |word| word.match?(/[*"]/) ? word : "#{word}*" }.join(" ")

      sanitized_query = conn.quote(fts_query)

      sql = "SELECT #{foreign_key_col} AS id FROM #{fts_table} WHERE #{fts_table} MATCH #{sanitized_query} ORDER BY rank"

      begin
        ids = conn.execute(sql).map(&:values).flatten
        where(id: ids)
      rescue SQLite3::SQLException, ActiveRecord::StatementInvalid => e
        # If FTS5 query has syntax errors, return empty result instead of raising
        Rails.logger.warn("FTS5 search error for query '#{query}': #{e.message}")
        none
      end
    }

    # Add exact search scope - uses double quotes to force exact phrase matching
    scope :exact_search, ->(query) {
      return none if query.blank?

      conn = connection
      fts_table = conn.quote_table_name("fts_#{table_name}")
      foreign_key_col = conn.quote_column_name(klass.to_s.foreign_key)

      # For exact matching in FTS5, wrap the query in double quotes
      # Remove dangerous characters first
      clean_query = query.gsub(/[;<>=]/, " ")
      # Then escape any double quotes in the original query
      exact_query = clean_query.gsub('"', '""')
      exact_query = %("#{exact_query}")

      sanitized_query = conn.quote(exact_query)

      sql = "SELECT #{foreign_key_col} AS id FROM #{fts_table} WHERE #{fts_table} MATCH #{sanitized_query} ORDER BY rank"

      begin
        ids = conn.execute(sql).map(&:values).flatten
        where(id: ids)
      rescue SQLite3::SQLException, ActiveRecord::StatementInvalid => e
        # If FTS5 query has syntax errors, return empty result instead of raising
        Rails.logger.warn("FTS5 exact search error for query '#{query}': #{e.message}")
        none
      end
    }
  end

  class_methods do
    def search_scope(*attrs)
      # Store the search scope attributes at the class level
      class_attribute :search_scope_attrs, default: attrs
    end

    def auto_update_search_index?
      auto_update_search_index
    end

    def rebuild_search_index(*ids)
      target_ids = Array(ids)
      target_ids = self.ids if target_ids.empty?

      conn = connection
      fts_table = conn.quote_table_name("fts_#{table_name}")
      foreign_key_col = conn.quote_column_name(to_s.foreign_key)

      # Delete existing records
      if target_ids.any?
        quoted_ids = target_ids.map { |id| conn.quote(id) }.join(", ")
        sql_delete = "DELETE FROM #{fts_table} WHERE #{foreign_key_col} IN (#{quoted_ids})"
        conn.execute(sql_delete)
      else
        sql_delete = "DELETE FROM #{fts_table}"
        conn.execute(sql_delete)
      end

      # Insert records
      target_ids.each do |id|
        # Use the model-specific search scope attributes
        record = where(id: id).pluck(*search_scope_attrs, :id).first
        if record.present?
          record_id = record.pop

          # Quote column names
          columns = search_scope_attrs.map { |attr| conn.quote_column_name(attr) }
          all_columns = (columns + [foreign_key_col]).join(", ")

          # Quote values
          values = record.map { |value| conn.quote(value || "") }
          all_values = (values + [conn.quote(record_id)]).join(", ")

          sql_insert = "INSERT INTO #{fts_table}(#{all_columns}) VALUES (#{all_values})"
          conn.execute(sql_insert)
        end
      end
    end

    def rebuild_search_index_in_batches(*ids, batch_size: 5000)
      target_ids = Array(ids)
      target_ids = self.ids if target_ids.empty?

      conn = connection
      fts_table = conn.quote_table_name("fts_#{table_name}")
      foreign_key_col = conn.quote_column_name(to_s.foreign_key)

      # Delete existing records
      if target_ids.any?
        quoted_ids = target_ids.map { |id| conn.quote(id) }.join(", ")
        sql_delete = "DELETE FROM #{fts_table} WHERE #{foreign_key_col} IN (#{quoted_ids})"
        conn.execute(sql_delete)
      else
        sql_delete = "DELETE FROM #{fts_table}"
        conn.execute(sql_delete)
      end

      # Track count for reporting instead of returning all IDs
      processed_count = 0

      # Quote column names once
      columns = search_scope_attrs.map { |attr| conn.quote_column_name(attr) }
      all_columns = (columns + [foreign_key_col]).join(", ")

      # Process in batches
      target_ids.in_groups_of(batch_size, false).each do |batch_ids|
        # Fetch records in batch using the model-specific search scope attributes
        records = if name == "Book"
          where(work_id: nil).where(id: batch_ids).pluck(*search_scope_attrs, :id)
        else
          where(id: batch_ids).pluck(*search_scope_attrs, :id)
        end

        next if records.empty?

        # Build bulk insert values with proper quoting
        values = records.map do |record|
          record_id = record.pop
          quoted_attrs = record.map { |value| conn.quote(value || "") }
          all_values = (quoted_attrs + [conn.quote(record_id)]).join(", ")
          "(#{all_values})"
        end

        # Bulk insert
        sql_insert = "INSERT INTO #{fts_table}(#{all_columns}) VALUES #{values.join(", ")}"
        conn.execute(sql_insert)

        processed_count += records.size
        # Print progress update without returning large result set
        puts "Processed #{processed_count} of #{target_ids.size} records" if (processed_count % (batch_size * 5) == 0)
      end

      # Return a simple message instead of all the IDs
      "Completed indexing #{processed_count} records"
    end

    def update_search_index_now
      update_search_index
    end
  end
end
