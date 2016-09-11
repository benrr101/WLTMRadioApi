require 'rufus-scheduler'

############################################################################
# Player Enqueue Task
# - This task will run every 5 seconds and check to see 1) how many tracks are currently enqueued
#   in MPD, and 2) is the current track has less than 10 seconds remaining. If the conditions are
#   met, a track from the buffer will be removed and added to the queue.
Rails.application.config.after_initialize do
  # Grab the singleton instance of the Rufus scheduler
  s = Rufus::Scheduler.singleton

  # Setup the task to run every 5 seconds
  s.every '5s' do
    # If there is less than one track in the queue or if the remaining time is less than
    # 10 seconds, add another one from the buffer
    mpd = Mpd.new
    remaining_time = mpd.remaining_time
    if remaining_time.nil? || remaining_time <= 10
      # Pop the top of the buffer
      buffer_file = BufferRecord.first
      buffer_file.destroy

      # Add it to MPD's queue
      Rails.logger.info('Adding track from buffer')
      Mpd.queue_add(buffer_file.absolute_path)

      # Add a history record of the track that was added
      HistoryRecord.Create(
         absolute_path: buffer_file.absolute_path,
         display_name: File.basename(buffer_file.absolute_path),
         on_behalf_of: buffer_file.on_behalf_of,
         bot_queued: buffer_file.bot_queued,
         played_time: DateTime.now + 10.seconds
      )
    else
      Rails.logger.info("Current track has #{remaining_time}s left, no tracks need adding")
    end
  end
end
