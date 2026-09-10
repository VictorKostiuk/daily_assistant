module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_api_user!, only: %i[signup login create_password update_password]

      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_body

      # Dummy bcrypt digest matching User.stretches, computed once at load so
      # missing and inactive logins spend the same time as a wrong-password check.
      DUMMY_PASSWORD_DIGEST = Devise::Encryptor.digest(User, "timing-oracle-dummy")

      # Credential-endpoint throttles, keyed by IP.
      # production.rb sets no cache_store, so Rails 8.1 uses FileStore at tmp/cache.
      # That store is per host. The IP key is spoofable via X-Forwarded-For;
      # mitigation is deployment configuration (trusted proxies), not this code.
      #
      # API login 10 + HTML login 10 per 3 minutes, independent counters
      # (20/3 min per IP). Signup: 5 per hour; password request: 5 per hour.
      rate_limit to: 10, within: 3.minutes, only: :login, name: "login",
        with: :render_too_many_requests
      rate_limit to: 5, within: 1.hour, only: :signup, name: "signup",
        with: :render_too_many_requests
      rate_limit to: 5, within: 1.hour, only: :create_password, name: "password",
        with: :render_too_many_requests

      def signup
        InputValidator.signup_time_zone!(request.request_parameters.merge(request.query_parameters))
        user = User.new(signup_params)
        if user.save
          render json: {
            id: user.id,
            email: user.email,
            first_name: user.first_name,
            last_name: user.last_name,
            time_zone: user.time_zone,
            locale: user.locale,
            role: user.role,
            status: user.status
          }, status: :created
        else
          render_validation_error(user.errors.messages)
        end
      end

      def login
        return if missing_params?(:email, :password)

        user = User.find_for_authentication(email: params[:email])
        unless authenticatable_user?(user, params[:password])
          return render_unauthorized
        end

        token, record = ApiToken.issue!(user: user)
        render json: {
          token: token,
          token_type: "Bearer",
          expires_at: record.expires_at.iso8601
        }
      end

      def logout
        current_api_token.update!(revoked_at: Time.current)
        head :no_content
      end

      def create_password
        return if missing_params?(:email)

        begin
          User.send_reset_password_instructions(email: params[:email])
        rescue StandardError => error
          Rails.logger.error(error.class.to_s)
        end
        render json: {}, status: :accepted
      end

      def update_password
        user = User.reset_password_by_token(
          reset_password_token: params[:reset_password_token],
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )

        if user.errors.empty?
          render json: {}
        else
          render_validation_error(user.errors.messages)
        end
      end

      private

      def authenticatable_user?(user, password)
        if user&.active?
          user.valid_password?(password)
        else
          Devise::Encryptor.compare(User, DUMMY_PASSWORD_DIGEST, password.to_s)
          false
        end
      end

      def signup_params
        params.permit(
          :email, :password, :password_confirmation,
          :first_name, :last_name, :time_zone, :locale
        )
      end

      def missing_params?(*keys)
        missing = keys.select { |key| params[key].blank? }
        return false if missing.empty?

        details = missing.index_with { [ "can't be blank" ] }
        render_validation_error(details)
        true
      end

      def render_validation_error(details)
        render_error(
          code: "validation_error",
          message: "Request is invalid",
          details: details,
          status: :unprocessable_content
        )
      end

      def render_malformed_body
        render_validation_error({ "base" => [ "is malformed" ] })
      end

      def render_too_many_requests
        render_error(code: "too_many_requests", message: "Too many requests", status: :too_many_requests)
      end
    end
  end
end
