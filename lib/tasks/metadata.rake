namespace :metadata do
  desc "Import JSON metadata"
  task import: ["db:drop", "db:create", "db:migrate"] do
    MediaManager.instance.import(job_id: "rake")
  end

  desc "Export JSON metadata."
  task export: :environment do
    MediaManager.instance.export(job_id: "rake")
  end

  desc "Scan the stash directory for new files"
  task scan: :environment do
    ScanService.run
  end

  desc "Enqueue preview generation for all videos"
  task generate_previews: :environment do
    videos = Video.all
    puts "Enqueuing preview generation for #{videos.count} videos..."
    videos.each { |video| GeneratePreviewJob.perform_later(video.id) }
  end

  desc "Queue remux/transcode jobs for all videos needing processing"
  task process_videos: :environment do
    videos = Video.needing_processing
    puts "Queuing #{videos.count} videos for processing..."
    videos.each { |video| TranscodeJob.perform_later(video.id) }
  end

  desc "Cleanup generated files for missing videos"
  task cleanup: :environment do
    MediaManager.instance.clean(job_id: "rake")
  end
end
