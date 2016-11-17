class Api::HistoryController < ApplicationController
  # GET /history/current
  def current
    current_track = HistoryRecord.includes(:track).order(:played_time).last
    render :json => current_track,
           :include => {:track => {
               :except => [:created_at, :updated_at, :id, :absolute_path],
               :methods => [:download_link, :folder_download_link]
           }},
           :except => [:created_at, :updated_at, :id, :track_id]
  end

  # GET /history/date?start=?[&end=?][&page=?&pagesize=?][&desc=true]
  def date
    # Sanity check the parameters
    error_message = nil
    if params[:start].nil?
      error_message = 'parameter start is required'
    end
    unless params[:start].is_a?(Numeric) || params[:start].to_i >= 0
      error_message = 'parameter start must be a positive integer'
    end
    start_date = params[:start].to_i
    unless params[:end].nil?
      unless params[:end].is_a?(Numeric) || params[:end].to_i >= 0
        error_message = 'parameter end must be a positive integer'
      end
      unless params[:end].to_i < start_date
        error_message = 'parameter end must be greater than start'
      end
    end
    if params[:pagesize].nil? ^ params[:page].nil?
      error_message = 'both page and pagesize parameters must be provided'
    end
    unless error_message.nil?
      render :json => { :errors => error_message },
             :status => :bad_request
      return
    end

    # Process the start date and create the base query
    start_date = DateTime.strptime(start_date.to_s, '%s')
    end_date = params[:end].nil? ? DateTime.now : DateTime.strptime(params[:end].to_s, '%s')
    tracks = HistoryRecord.includes(:track).order(:played_time).where(:played_time => start_date..end_date)

    # Reverse order if DESC is provided
    if !params[:desc].nil? && params[:desc] == 'true'
      tracks = tracks.reverse_order
    end

    # Add pagination if it was requested, otherwise we'll assume the default
    page_size = params[:pagesize].nil? ? 100 : params[:pagesize].to_i
    page = params[:page].nil? ? 0 : params[:page].to_i
    tracks = tracks.offset(page_size * page).limit(page_size)

    render :json => tracks,
           :include => {:track => {
               :except => [:created_at, :updated_at, :id, :absolute_path],
               :methods => [:download_link, :folder_download_link]
           }},
           :except => [:created_at, :updated_at, :id, :track_id]
  end
end
