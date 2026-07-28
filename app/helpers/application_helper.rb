module ApplicationHelper
  def public_asset_version(filename)
    path = Rails.root.join("public", filename)

    File.exist?(path) ? File.mtime(path).to_i : Rails.application.config.assets.version
  end

  def public_icon_path(filename)
    "/#{filename}?v=#{public_asset_version(filename)}"
  end

  def public_png_dimensions(filename)
    path = Rails.root.join("public", filename)
    return "512x512" unless File.exist?(path)

    File.open(path, "rb") do |file|
      return "512x512" unless file.read(8) == "\x89PNG\r\n\x1A\n".b

      file.read(8)
      width = file.read(4).unpack1("N")
      height = file.read(4).unpack1("N")

      "#{width}x#{height}"
    end
  end
end
