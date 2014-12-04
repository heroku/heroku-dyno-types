PROCESS_TIERS = JSON.parse <<EOF
[
  { "tier": "free",        "max_scale": 1,   "max_processes": 2,    "cost": { "Free": 0 } },
  { "tier": "basic",       "max_scale": 1,   "max_processes": null, "cost": { "Basic": 700 } },
  { "tier": "standard",    "max_scale": 100, "max_processes": null, "cost": { "Standard": 2500 } },
  { "tier": "production",  "max_scale": 100, "max_processes": null, "cost": { "Production": 5000, "Performance": 50000 } },
  { "tier": "traditional", "max_scale": 100, "max_processes": null, "cost": { "1X": 3600, "2X": 7200, "PX": 57600 } }
]
EOF

# calculate approximate dollars per hour for each dyno type
costs = PROCESS_TIERS.collect do |tier|
  tier["cost"].collect do |name, cents_per_month|
    [name, (cents_per_month / 720.0).floor / 100.0]
  end
end

# redefine Heroku::Command:Ps::PRICES without warning
# http://stackoverflow.com/questions/3375360/how-to-redefine-a-ruby-constant-without-warning
prices = Hash[*costs.flatten]
Heroku::Command::Ps.send(:remove_const, :PRICES)
Heroku::Command::Ps.const_set(:PRICES, prices)

class Heroku::Command::Ps
  # ps:tier [traditional|free|standard|basic|production]
  #
  # resize and scale all process types between different process tiers
  #
  #Examples:
  #
  # $ heroku ps:tier
  # Running web at 1:Free ($0/mo), worker at 1:Free ($0/mo).
  #
  # $ heroku ps:tier basic
  # Changing process tier... done, now running web at 1:basic ($9/mo), worker at 1:basic ($9/mo)
  #
  # $ heroku ps:scale web=2
  # Scaling dynos... failed
  #  !    Cannot scale to more than 1 basic size dynos per process type.
  #
  # $ heroku ps:tier production
  # Changing process tier... done, now running web at 1:Production ($30/mo), worker at 1:Production ($30/mo).
  #
  # $ heroku ps:scale web=2
  # Scaling dynos... done, now running web at 2:Production.
  #
  # $ heroku ps:tier basic
  # Changing process tier... done, now running web at 1:Basic ($9/mo), worker at 1:Basic ($9/mo)

  def tier
    app
    process_tier = shift_argument
    validate_arguments!

    # get or update app.process_tier
    if !process_tier.nil?
      print "Changing process tier... "

      api_tier = process_tier.downcase
      if api_tier == "traditional"
        api_tier = nil
      end

      app_resp = api.request(
        :method  => :patch,
        :path    => "/apps/#{app}",
        :body    => json_encode("process_tier" => api_tier),
        :headers => {
          "Accept"       => "application/vnd.heroku+json; version=edge",
          "Content-Type" => "application/json"
        }
      )

      if app_resp.status != 200
        puts "failed"
        error app_resp.body["message"] + " Please use `heroku ps:scale` to change process size and scale."
      end

      print "done. "
    else
      app_resp = api.request(
        :expects => 200,
        :method  => :get,
        :path    => "/apps/#{app}",
        :headers => {
          "Accept"       => "application/vnd.heroku+json; version=edge",
          "Content-Type" => "application/json"
        }
      )
    end

    # get, calculate and display app process type costs
    formation_resp = api.request(
      :expects => 200,
      :method  => :get,
      :path    => "/apps/#{app}/formation",
      :headers => {
        "Accept"       => "application/vnd.heroku+json; version=3",
        "Content-Type" => "application/json"
      }
    )

    tier_info = PROCESS_TIERS.detect { |t| t["tier"] == app_resp.body["process_tier"] }

    if app_resp.body["process_tier"] == "legacy"
      error "Process tiers are not available for this app. Please use `heroku ps:scale` to change process size and scale."
    end

    ps_costs = formation_resp.body.map do |ps|
      cost = tier_info["cost"][ps["size"]] * ps["quantity"] / 100
      "#{ps['type']} at #{ps['quantity']}:#{ps["size"]} ($#{cost}/mo)"
    end

    if ps_costs.empty?
      ps_costs = tier_info["cost"].map do |size, cost|
        "#{size} ($#{cost/100}/mo)"
      end
      puts "Running no #{ps_costs.join(", ")} processes."
    else
      puts "Running #{ps_costs.join(', ')}."
    end
  end
end
