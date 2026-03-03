class Library::Backend
  attr_reader :library

  def initialize(library)
    @library = library
  end

  def list_files(extensions:)
    raise NotImplementedError
  end

  def file_exists?(relative_path)
    raise NotImplementedError
  end

  def ffmpeg_input(relative_path)
    raise NotImplementedError
  end

  def file_size(relative_path)
    raise NotImplementedError
  end

  def read_range(relative_path, range)
    raise NotImplementedError
  end

  def absolute_path(relative_path)
    raise NotImplementedError
  end

  def local?
    false
  end

  def remote?
    !local?
  end
end
