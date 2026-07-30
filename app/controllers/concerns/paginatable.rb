module Paginatable
  extend ActiveSupport::Concern

  Pagination = Struct.new(:records, :page, :per_page, :total, keyword_init: true) do
    def total_pages
      return 0 if total.zero?

      (total.to_f / per_page).ceil
    end
  end

  PER_PAGE = 25

  private

  def paginate(scope, per_page: PER_PAGE)
    page = params[:page].to_i
    page = 1 if page < 1

    Pagination.new(
      records: scope.limit(per_page).offset((page - 1) * per_page),
      page: page,
      per_page: per_page,
      total: scope.count
    )
  end
end
