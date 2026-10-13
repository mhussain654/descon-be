# frozen_string_literal: true

# A candidate's preferred language may be unknown until they first use the
# app (e.g. imported candidates whose file left it blank): it is then recorded
# from the language they choose at sign-in. The existing check constraint
# still limits any set value to en/ur (NULL passes a CHECK).
class AllowUnsetCandidatePreferredLocale < ActiveRecord::Migration[8.1]
  def change
    change_table :candidates, bulk: true do |t|
      t.change_null :preferred_locale, true
      t.change_default :preferred_locale, from: 'en', to: nil
    end
  end
end
