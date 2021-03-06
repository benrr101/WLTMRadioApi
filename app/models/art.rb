require 'taglib'
require 'taglib/id3v1'
require 'taglib/id3v2'
require 'taglib/flac'
require 'taglib/aiff'
require 'taglib/ogg'
require 'taglib/wav'

class Art < ApplicationRecord
  has_many :track

  def self.serializable_hash_options
    {
        :methods => [:art_link],
        :except => [:created_at, :updated_at, :hash_code, :id, :bytes],
    }
  end

  def self.create_from_file(path)
    unless File.exists?(path)
      Rails.logger.warn("Failed to create art record: File does not exist #{path}")
      return nil
    end

    # Step 1: Get the image file to store
    # Attempt 1: Load the art from the metadata
    mimetype = nil
    bytes = nil
    case File.extname(path).split('.').last
      when 'mp3', 'm4a'
        id3v2_file = TagLib::MPEG::File.new(path)
        id3v2_tag = id3v2_file.id3v2_tag
        if id3v2_tag.frame_list('APIC').any?
          pic = id3v2_tag.frame_list('APIC').first
          mimetype = pic.mime_type
          bytes = pic.picture
        end
        id3v2_file.close
      when 'flac'
        tag_file = TagLib::FLAC::File.new(path)
        unless tag_file.picture_list[0].nil?
          pic = tag_file.picture_list[0]
          mimetype = pic.mime_type
          bytes = pic.data
        end
        tag_file.close
      else
        mimetype = nil
        bytes = nil
    end

    # Attempt 2: Find any image files in the folder
    if mimetype.nil?
      image_files = FileSystem.get_all_image_files(path)
      if not(image_files.nil?) and image_files.any?
        image_file = image_files[0]
        mimetype = FileSystem.get_image_mimetype(image_file)
        bytes = open(image_file, 'rb') { |file| file.read }
      end
    end

    # If we *still* don't have an image, just give up
    if mimetype.nil?
      return nil
    end

    # Step 2: Calculate the hash of the image bytes
    hash = Digest::SHA256.hexdigest(bytes)

    # Step 3: If the mimetype we discovered isn't a mimetype, try again
    unless mimetype.include?('/')
      mimetype = FileSystem.get_extension_mimetype(mimetype)
    end
    if mimetype.include?('(null)')
      mimetype = FileSystem.default_mimetype
    end

    # Step 3: Store the image in the database
    begin
      return Art.where(:hash_code => hash).first_or_create! do |art|
        art.mimetype = mimetype
        art.bytes = bytes
      end
    rescue => e
      Rails.logger.warn("Failed to create/find Art. #{e}")
      return nil
    end
  end

  def art_link
    "/api/art/#{hash_code}"
  end

end