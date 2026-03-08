module Scannable
  extend ActiveSupport::Concern

  def scan(job_id:, library_id: nil)
    @logs = []

    @current = 0
    @total = 0
    libraries = library_id ? Library.where(id: library_id) : Library.all
    libraries.each do |library|
      scan_paths = library.backend.list_files(extensions: Canister::MEDIA_EXTENSIONS)
      @total += scan_paths.count
      info("Starting scan of #{scan_paths.count} files in #{library.name} (#{library.path})")
      scan_paths.each { |relative_path|
        @current += 1
        try {
          scan_task = ScanService.new(path: relative_path, library: library)
          scan_task.start
        }
      }
    end
  end
end