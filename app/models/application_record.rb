# frozen_string_literal: true

# Abstract base class that every Active Record model in the app inherits from.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
