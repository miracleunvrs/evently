class CategoriesController < ApplicationController
  def index
    render json: Category.order(:id).as_json(only: %i[id slug title])
  end
end
