# frozen_string_literal: true

module Api
  module V1
    class Downloads < Grape::API
      helpers Api::V1::ControllerHelpers

      resource :downloads do
        desc 'Download do Build Básico' do
          summary 'Download do código fonte básico (Site + Admin)'
          security [{ Bearer: [] }]
        end
        get :basic do
          # Auth já é feita pelo Api::Root
          
          # Check permission
          has_permission = UserPermission.where(user: current_user)
                                        .joins(:permission)
                                        .where(permissions: { key: %w[download_basic download_full] })
                                        .where(revoked_at: nil)
                                        .exists?
                                        
          error!('Acesso negado. Adquira o plano Básico ou Completo.', 403) unless has_permission

          file_path = Rails.root.join('storage', 'builds', 'build_basic.zip')
          
          # Placeholder generation if not exists (dev only)
          unless File.exist?(file_path)
            if Rails.env.development?
              FileUtils.mkdir_p(File.dirname(file_path))
              File.write(file_path, "DUMMY CONTENT BASIC BUILD")
            else
               error!({ error: 'Arquivo de build não encontrado' }, 404)
            end
          end
          
          content_type 'application/zip'
          header['Content-Disposition'] = 'attachment; filename="ai9_build_basic.zip"'
          env['api.format'] = :binary
          
          body File.binread(file_path)
        end

        desc 'Download do Build Completo' do
          summary 'Download do código fonte completo (SaaS)'
          security [{ Bearer: [] }]
        end
        get :full do
          # Auth já é feita pelo Api::Root

          # Check permission
          has_permission = UserPermission.where(user: current_user)
                                        .joins(:permission)
                                        .where(permissions: { key: 'download_full' })
                                        .where(revoked_at: nil)
                                        .exists?

          error!('Acesso negado. Adquira o plano Completo.', 403) unless has_permission

          file_path = Rails.root.join('storage', 'builds', 'build_full.zip')
          
          # Placeholder (dev only)
          unless File.exist?(file_path)
            if Rails.env.development?
              FileUtils.mkdir_p(File.dirname(file_path))
              File.write(file_path, "DUMMY CONTENT FULL BUILD")
            else
              error!({ error: 'Arquivo de build não encontrado' }, 404)
            end
          end

          content_type 'application/zip'
          header['Content-Disposition'] = 'attachment; filename="ai9_build_full.zip"'
          env['api.format'] = :binary

          body File.binread(file_path)
        end
      end
    end
  end
end
