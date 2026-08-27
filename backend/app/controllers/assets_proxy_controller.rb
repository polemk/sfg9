# frozen_string_literal: true

# Controller para servir arquivos estáticos da pasta public/uploads 
# com o MIME type correto, contornando limitações de servidores estáticos em dev
class AssetsProxyController < ActionController::Base
  def show
    path = Rails.root.join('public', 'uploads', params[:path])
    ext = File.extname(path).downcase
    
    if File.exist?(path) && !File.directory?(path)
      # Mapeamento básico de tipos MIME
      mime_type = case ext
                  when '.mp3' then 'audio/mpeg'
                  when '.ogg' then 'audio/ogg'
                  when '.wav' then 'audio/wav'
                  when '.png' then 'image/png'
                  when '.jpg', '.jpeg' then 'image/jpeg'
                  when '.gif' then 'image/gif'
                  when '.pdf' then 'application/pdf'
                  else Rack::Mime.mime_type(ext, 'application/octet-stream')
                  end

      send_file path, type: mime_type, disposition: 'inline'
    else
      render plain: 'Not Found', status: :not_found
    end
  end
end
