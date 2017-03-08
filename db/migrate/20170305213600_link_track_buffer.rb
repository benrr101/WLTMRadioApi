class LinkTrackBuffer < ActiveRecord::Migration

  def change
    # Create a new reference between track and buffer
    add_reference :buffer_records, :track, index: true
    add_foreign_key :buffer_records, :tracks

    # Ensure that the track for each buffer is set correctly
    BufferRecord.all.each do |record|
      say("Updating #{record.absolute_path}", :subitem)
      begin
        track = Track.create_from_file(record.absolute_path)
        record.update_attribute(:track_id, track.id)
      rescue
        say("Failed to update #{record.absolute_path}!", :subitem)
        record.destroy
      end
    end

    # Drop the absolute path
    remove_column :buffer_records, :absolute_path

  end

end