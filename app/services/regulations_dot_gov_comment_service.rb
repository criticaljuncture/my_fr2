class RegulationsDotGovCommentService
  attr_reader :args, :comment, :remote_ip, :api_key_type
  attr_accessor :comment_form

  delegate :document_number, to: :@comment

  class MissingCommentUrl < StandardError; end

  HOURLY_SUBMISSION_LIMIT = 10

  def initialize(remote_ip, args)
    @remote_ip = remote_ip
    @args = args

    @comment = Comment.new
    @comment.document_number = @args.delete(:document_number)
  end

  def build_comment
    load_comment_form
    assign_attributes_to_comment
  end

  def load_comment_form(api_options={})
    HTTParty::HTTPCache.reading_from_cache(
      api_options.fetch(:read_from_cache) { true }
    ) do
      client = RegulationsDotGov::Client.new
      client.class.api_key = Rails.application.secrets[:data_dot_gov][:primary_comment_api_key]

      if comment.document.comment_url
        @comment_form = client.get_comment_form(comment.regulations_dot_gov_document_id)
        comment.comment_form = comment_form
      else
        raise MissingCommentUrl
      end
    end
  end

  def assign_attributes_to_comment
    begin
      if args[:comment]
        comment_params = sanitize_comment_params(args[:comment])
        comment.secret = comment_params[:secret]

        # replace line endings that cause char count problems
        if comment_params["general_comment"].present?
          comment_params["general_comment"].gsub!(/\r\n/, "\n")
        end

        comment.attributes = comment_params
      end
    rescue => exception
      record_regulations_dot_gov_error(exception)
    end
  end

  def sanitize_comment_params(comment_params)
    comment_params.except(
      :agency_name,
      :agency_participating,
      :checked_comment_publication_at,
      :comment_publication_notification,
      :comment_tracking_number,
      :created_at,
      :document_number,
      :encrypted_comment_data,
      :id,
      :iv,
      :salt,
      :submission_key,
      :user_id,
    )
  end

  def send_to_regulations_dot_gov(submission_type=:submit)
    Dir.mktmpdir do |dir|
      args = {
        comment_on: comment_form.document_id,
        submit: "Submit Comment"
      }.merge(
        comment_form.fields.inject({}){|hsh, field|
          hsh[field.name] = comment.send(field.name)
          hsh
        }
      )

      args[:uploadedFile] = comment.attachments.map do |attachment|
        File.open(attachment.decrypt_to(dir))
      end

      if submission_type == :submit
        begin
          submit_comment(args)
        rescue RegulationsDotGov::Client::InvalidSubmission => exception
          record_regulations_dot_gov_error(exception)

          # comment form may have changed since last retrieved
          reload_comment_form_and_resubmit(exception)
        rescue RegulationsDotGov::Client::OverRateLimit => exception
          notify = bulk_submission? ? false : true
          record_regulations_dot_gov_error(exception, notify)
          return exception
        rescue RegulationsDotGov::Client::ResponseError => exception
          record_regulations_dot_gov_error(exception, notify)

          comment.add_error(
            I18n.t(
              'regulations_dot_gov_errors.unknown.modal_html',
              regulations_dot_gov_link: @comment.document.comment_url
            )
          )
          return exception
        end
      elsif submission_type == :resubmit
        begin
          submit_comment(args)
        # our re-submission could also have an error
        # we just return that and don't attempt any more niceties
        rescue RegulationsDotGov::Client::ResponseError => inner_exception
          notify = inner_exception.is_a?(RegulationsDotGov::Client::InvalidSubmission) ? false : true
          record_regulations_dot_gov_error(inner_exception, notify)

          # show form to user but with message from regulations.gov
          regulation_dot_gov_error = RegulationsDotGovError.new(inner_exception)
          message = regulation_dot_gov_error.message

          # add a note about long message - char counts aren't calculated the same
          # between systems leading to inadvertant over char limit messages at the
          # boundary (multibyte chars are counted more than once by regulations.gov)
          if regulation_dot_gov_error.respond_to?(:[]) && regulation_dot_gov_error["longFields"].present?
            if regulation_dot_gov_error["longFields"] == ["general_comment"]
              message += "<br><br> If you are attempting to submit a comment of substantial length we recommend adding the comment as a file attachment below instead."
            else
              regulation_dot_gov_error["longFields"].each do |field|
                message += "<br><br> #{field} exceeds maximum length."
              end
            end
          end

          comment.add_error(message)
          return inner_exception
        end
      end
    end
  end

  def record_regulations_dot_gov_error(exception, notify=true)
    Rails.logger.error(exception)
    Honeybadger.notify(exception) if notify
  end

  def increment_comment_tracking_keys
    $redis.incr hourly_comment_tracking_key
    $redis.expire hourly_comment_tracking_key, 2.hours

    if hourly_requests_for_ip == HOURLY_SUBMISSION_LIMIT
      $redis.incrby bulk_totals_comment_tracking_key, HOURLY_SUBMISSION_LIMIT
    elsif hourly_requests_for_ip > HOURLY_SUBMISSION_LIMIT
      $redis.incr bulk_totals_comment_tracking_key
    end
  end

  def api_key
    return @api_key if @api_key

    if hourly_requests_for_ip >= HOURLY_SUBMISSION_LIMIT
      @api_key = Rails.application.secrets[:data_dot_gov][:secondary_comment_api_key]
    else
      @api_key = Rails.application.secrets[:data_dot_gov][:primary_comment_api_key]
    end

    @api_key
  end

  def bulk_submission?
    api_key == Rails.application.secrets[:data_dot_gov][:secondary_comment_api_key]
  end

  def hourly_requests_for_ip
    $redis.get(hourly_comment_tracking_key).to_i
  end

  def hourly_comment_tracking_key
    "cc:#{Time.current.hour}:#{document_number}:#{hashed_remote_ip}"
  end

  def daily_bulk_requests_for_ip
    $redis.get(bulk_totals_comment_tracking_key).to_i
  end

  def bulk_totals_comment_tracking_key
    "cc_bulk_totals:#{Date.current.to_s(:iso)}:#{document_number}:#{remote_ip}"
  end

  def hashed_remote_ip
    Digest::MD5.hexdigest "#{Rails.application.secrets[:comment_ip_salt]}#{remote_ip}"
  end

  def submit_comment(args)
    increment_comment_tracking_keys

    comment_form.client.class.api_key = api_key

    if Settings.feature_flags.regulations_dot_gov.submit_comments
      comment_form.client.submit_comment(args)
    else
      #stub a return object
      RegulationsDotGov::CommentFormResponse.new(nil,
        {
          "status" => 200,
          "trackingNumber" => "STUBBED-#{SecureRandom.hex(7)}",
        }
      )
    end
  end

  def reload_comment_form_and_resubmit(exception)
    # reload the form from regs.gov
    load_comment_form(:read_from_cache => false)

    if comment.valid?
      # resend the updated form with the current data
      response = send_to_regulations_dot_gov(:resubmit)
      return response
    else
      # return the exception
      # comment has been updated and will show invalid form to user with our error messages
      # ex: a required field was added after the form was last cached by us
      return exception
    end
  end

  class RegulationsDotGovError
    attr_reader :exception

    def initialize(exception)
      @exception = exception
    end

    def message
      @message ||= parse_message
    end

    private

    # sometimes the message is a json encoded string
    # other times it's just a string
    def parse_message
      begin
        JSON.parse(exception.message)["message"]
      rescue JSON::ParserError
        exception.message
      end
    end
  end
end
