class ApplicationController < ActionController::Base
  before_action :redirect_naked_domain

  private

  # 1️⃣ Redirect naked domain → www
  def redirect_naked_domain
    if request.host == "1245consulting.com"
      redirect_to "https://www.1245consulting.com#{request.fullpath}",
                  status: :moved_permanently
    end
  end                                     # ← close the method here ❗️

  # 2️⃣ Devise: where to go after sign-in
  def after_sign_in_path_for(resource)
    resource.paying_customer? ? dashboard_index_path : subscribe_index_path
  end

  # 3️⃣ Your onboarding helper
  def maybe_skip_onboarding
    redirect_to dashboard_index_path, notice: "You're already subscribed" if current_user.finished_onboarding?
  end
end
