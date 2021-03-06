require 'sys/filesystem'
require 'taglib'

class FileSystem

  # Status of the filesystem space usage
  class Status

    # Initializes a Status class by calculating the
    # @param <Sys::Filesystem::Stat> stat Statistics object from sys/filesystem
    def initialize(stat)
      @total_gb = stat.blocks * stat.block_size / 1024 / 1024 / 1024
      @free_gb = stat.blocks_free * stat.block_size / 1024 / 1024 / 1024
      @inuse_gb = (stat.blocks - stat.blocks_free) * stat.block_size / 1024 / 1024 / 1024

      @inuse_percent = @inuse_gb.to_f / @total_gb * 100.0
      @inuse_percent = @inuse_percent.round(1)
      @free_percent = 100 - @inuse_percent
    end

    # @return <Integer> Total number of GB for the base path
    def total_gb
      @total_gb
    end

    # @return <Integer> Number of GB free for the base path
    def free_gb
      @free_gb
    end

    # @return <Integer> Number of GB in use for the base path
    def inuse_gb
      @inuse_gb
    end

    # @return <Float> Percentage of base path in use
    def inuse_percent
      @inuse_percent
    end

    # @return <Float> Percentage of base path free
    def free_percent
      @free_percent
    end

  end

  # CLASS METHODS ##########################################################

  # A mimetype to default to if everything fails
  def self.default_mimetype
    return 'application/octet-stream'
  end

  # Returns the minimum amount of path in order to get unique search terms
  # @param [Array<String>] ambiguous_items The ambiguous items
  # @return [Array<String>] The disambiguated items
  def self.disambiguate_items(ambiguous_items)
    # Turn the ambiguous list into a list of [dirname, basename]
    # @type [Array<Array<String>>]
    working_list = ambiguous_items.map {|e| [File.dirname(e), File.basename(e)]}

    # Process until the working list is empty (ie, no dupes)
    # @type [Array<String>]
    output = []
    until working_list.size == 0
      dupes = []
      working_list.group_by {|e| e[1]}.each do |k, v|
        if v.size == 1
          output.push(k)
        else
          v.each do |dupe|
            # Shift the last element of the path into the disambiguated name
            dupes.push([File.dirname(dupe[0]), File.join(File.basename(dupe[0]), dupe[1])])
          end
        end
      end
      working_list = dupes
    end

    return output
  end

  # Retrieve statistics about free space
  # @return [FileSystem::Stats] Statistics about the space used on the base path
  def self.get_status
    # Get the stats for the root of the installation
    stat = Sys::Filesystem.stat(Rails.configuration.files['base_path'])
    return FileSystem::Status.new(stat)
  end

  # Retrieves all folders that files can be pulled from
  # @return [Array[string]] Array of folder paths to pull from
  def self.get_all_folders
    Rails.cache.fetch('filesystem/folders', expires_in: 1.hours) do
      # Glob the base folders
      base_folders = []
      Rails.configuration.files['included_folders'].each do |folder|
        folder = File.join(Rails.configuration.files['base_path'], folder)
        base_folders += Dir.glob(folder)
      end
      base_folders
    end
  end

  # Determines what files should be included in the shuffle
  # @return [Array[string]] An array of strings that should be shuffled
  def self.get_all_shuffle_files
    # Get te

    # Select the base folder for this selection
    base_folders = self.get_all_folders
    base_folder_selection = PersistentSettings.preincrement_with_wrap(PersistentSettings::RoundRobinIdKey, base_folders.length)
    selected_base_folder = base_folders[base_folder_selection]
    Rails.logger.debug("Picking file from selected base folder #{base_folder_selection} #{selected_base_folder}")

    # Generate globs for the different filetypes
    glob = File.join(selected_base_folder, "**/*.#{self.audio_filetype_glob}")
    return Dir.glob(glob)
  end

  # Fetches a list of all tracks that are in a given folder, ordered by track number or file name
  # if any of the files are missing track numbers.
  # @param folder [string]  The absolute path of the folder to get all tracks from
  # @return [Array[string]] An arry of all files in the folder
  def self.get_all_folder_files(folder)
    # Generate files that are in the folder
    glob = File.join(folder, "*.#{self.audio_filetype_glob}")
    files = Dir.glob(glob)

    # Sort the files by track number or by filename
    track_numbers = {}
    return files.sort do |x, y|
      x_track = track_numbers[x].nil? ? self.get_file_sort(x) : track_numbers[x]
      y_track = track_numbers[y].nil? ? self.get_file_sort(y) : track_numbers[y]

      # If either of the tracks don't have track numbers, use filenames instead
      if x_track == '' || y_track == ''
        next x <=> y
      end

      # Otherwise sort by track number
      next x_track <=> y_track
     end
  end

  # Fetches a list of all images in the folder of a given audio file
  # @param folder [string]  The absolute path of the audio file to get images from
  # @return [Array[string]]  An array of all images files in the folder that contains the audio
  def self.get_all_image_files(audio_path)
    # Figure out which folder the audio is in
    folder = File.dirname(audio_path)

    # Generate files that are in the folder
    glob = File.join(folder, "*.#{self.image_filetype_glob}")
    return Dir.glob(glob)
  end

  # Attempts to determine the mimetype of the given image based on extension
  # @param image_path [string] Absolute path to the audio file
  # @return [string] The mimetype based on the file's extension
  def self.get_image_mimetype(image_path)
    return self.get_extension_mimetype(File.extname(image_path).split('.').last)
  end

  # Attempts to determine the mimetype based on the extension provided
  # @param extension [string] The string for the extension to determine the mimetype of
  # @return [string] The mimetype based on the extension
  def self.get_extension_mimetype(extension)
    case extension
      when 'png', 'PNG'
        return 'image/png'
      when 'jpg', 'JPG', 'jpeg', 'JPEG'
        return 'image/jpeg'
      when 'bmp', 'BMP'
        return 'image/bmp'
      when 'gif', 'GIF'
        return 'image/gif'
      else
        return self.default_mimetype
    end
  end

  # Calculates the uploader of the track
  # @param path [string]  The absolute path of the track
  # @return [string]  The uploader of the track
  def self.get_track_uploader(path)
    # Strip off the base path
    working_path = path.sub(Rails.configuration.files['base_path'], '')

    # Strip off any leading slash
    working_path.sub!(/^#{File::Separator}/, '')

    # Take the first split folder as the uploader
    return working_path.split(File::Separator)[0]
  end

  # Searches the included folders for folders that match the search term
  # @param folder [string]  The search term for the folder to lookup
  # @return [Array[string]] All folders that match the search term
  def self.search_for_folder(folder)
    self.search_for_item("**/*#{folder}*/")
  end

  # Searches the included folders for files that match the search term
  # @param file [String]  The search term for the file to lookup
  # @return [Array<String>] All files that match the search term
  def self.search_for_file(file)
    if Rails.configuration.files['allowed_extensions'].any? {|ext| file.ends_with?('.' + ext)}
      # The search term included an audio extension, omit it from the globbing
      return self.search_for_item("**/*#{file}*")
    else
      # Search term did not include an audio extension, so add them to the globbing
      return self.search_for_item("**/*#{file}*.#{self.audio_filetype_glob}")
    end
  end

  # PRIVATE HELPERS ########################################################
  private
  def self.audio_filetype_glob
    '{' + Rails.configuration.files['allowed_extensions'].join(',') + '}'
  end

  def self.image_filetype_glob
    '{' + Rails.configuration.files['allowed_image_extensions'].join(',') + '}'
  end

  def self.search_for_item(search_term)
    if search_term.nil? || search_term.length == 0
      return []
    end

    # Process the search term into a fancypants glob
    search_glob = search_term.gsub(' ', '*')                 # Make space match space, dash, or underscore

    # Get all the included folders to source from
    match_items = []
    self.get_all_folders.each do |source_folder|
      glob_matches = Dir.glob(File.join(source_folder, search_glob), File::FNM_CASEFOLD)

      # Add all the matches to the list of matches
      match_items += glob_matches
    end
    return match_items
  end

  # Using TagLib looks up the track number of the file.
  # @param [String] path Absolute path to the file to read
  # @return [Integer] The track number
  def self.get_file_sort(path)
    # Read the file with a fallback
    track_number = 0
    begin
      TagLib::FileRef.open(path) do |tag_file|
        track_number = tag_file.tag.track
      end
    rescue
      track_number = 0
    end

    # Use empty string to indicate track number cannot come from tag file
    return '' if track_number == 0

    # Pad the track number with 0
    track_number.to_s.rjust(2, '0')
  end
end