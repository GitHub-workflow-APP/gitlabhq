# frozen_string_literal: true

module Organizations
  class UserOrganizationsFinder
    def initialize(current_user, target_user, params = {})
      @current_user = current_user
      @target_user = target_user
      @params = params
    end

    def execute
      return Organizations::Organization.none unless can_read_user_organizations?
      return Organizations::Organization.none if target_user.blank?

      target_user.organizations
    end

    private

    attr_reader :current_user, :target_user, :params

    def can_read_user_organizations?
      current_user&.can?(:read_user_organizations, target_user)
    end
  end
end
