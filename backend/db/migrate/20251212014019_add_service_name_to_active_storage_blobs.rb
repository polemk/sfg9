class AddServiceNameToActiveStorageBlobs < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:active_storage_blobs, :service_name)
      add_column :active_storage_blobs, :service_name, :string

      if defined?(ActiveStorage::Blob)
        ActiveStorage::Blob.where(service_name: nil).update_all(service_name: "local")
      end

      change_column_null :active_storage_blobs, :service_name, false, "local"
    end
  end
end
