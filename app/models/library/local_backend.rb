class Library::LocalBackend < Library::Backend
  def list_files(extensions:)
    return [] unless Dir.exist?(base_path)

    pattern = File.join(base_path, "**", "*.{#{extensions.join(",")}}")
    Dir.glob(pattern).map { |f| Pathname.new(f).relative_path_from(base_path).to_s }
  end

  def file_exists?(relative_path)
    File.exist?(absolute_path(relative_path))
  end

  def ffmpeg_input(relative_path)
    absolute_path(relative_path)
  end

  def file_size(relative_path)
    File.size(absolute_path(relative_path))
  rescue Errno::ENOENT
    nil
  end

  def read_range(relative_path, range)
    File.open(absolute_path(relative_path), "rb") do |f|
      if range.is_a?(Range)
        f.seek(range.begin)
        f.read(range.end - range.begin + 1)
      elsif range.is_a?(Integer)
        f.seek(range)
        f.read(64 * 1024)
      else
        f.read
      end
    end
  rescue Errno::ENOENT
    nil
  end

  def absolute_path(relative_path)
    File.join(base_path, relative_path)
  end

  def local?
    true
  end

  private

  def base_path
    Rails.root.join(library.path.to_s.sub(%r{^/}, ""))
  end
end
