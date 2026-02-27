module ApplicationHelper
  def nav_link_class(section)
    active = request.path.start_with?("/#{section}")
    base = "text-sm font-medium transition-colors"
    active ? "#{base} text-indigo-600" : "#{base} text-gray-600 hover:text-gray-900"
  end

  def rating_stars(rating)
    return "" unless rating
    full = (rating.to_f / 20).round
    full = full.clamp(0, 5)
    safe_join((1..5).map { |i|
      content_tag(:span, "★", class: i <= full ? "text-amber-400" : "text-gray-300")
    })
  end

  def format_duration(seconds)
    return "" unless seconds
    total = seconds.to_i
    h = total / 3600
    m = (total % 3600) / 60
    s = total % 60
    h > 0 ? format("%d:%02d:%02d", h, m, s) : format("%d:%02d", m, s)
  end

  def format_filesize(size)
    return "" unless size
    bytes = size.to_i
    if bytes >= 1_073_741_824
      format("%.1f GB", bytes.to_f / 1_073_741_824)
    elsif bytes >= 1_048_576
      format("%.1f MB", bytes.to_f / 1_048_576)
    else
      format("%.1f KB", bytes.to_f / 1_024)
    end
  end
end
