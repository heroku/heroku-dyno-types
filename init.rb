# redefined Heroku::Command:Ps::PRICES without warning
# http://stackoverflow.com/questions/3375360/how-to-redefine-a-ruby-constant-without-warning

prices = {
  "Free"        =>    0.0 / 720,
  "Hobby"       =>   9.00 / 720,
  "Production"  =>  30.00 / 720,
  "PX"          => 500.00 / 720, 
}

Heroku::Command::Ps.send(:remove_const, :PRICES)
Heroku::Command::Ps.const_set(:PRICES, prices)

PROCESS_TIERS = JSON.parse <<EOF
[
  { "tier": "free",       "max_scale": 1,   "max_processes": 2,    "cost": { "Free": 0 } },
  { "tier": "hobby",      "max_scale": 1,   "max_processes": null, "cost": { "Hobby": 900 } },
  { "tier": "production", "max_scale": 100, "max_processes": null, "cost": { "Standard": 3000, "Performance": 500000 } },
  { "tier": "legacy",     "max_scale": 100, "max_processes": null, "cost": { "1X": 3000, "2X": 6000, "PX": 500000 } }
]
EOF

class Heroku::Command::Ps
  # ps:tier [free|hobby|production]
  #
  # resize and scale dynos between different tiers
  #
  #Examples:
  #
  # $ heroku ps:tier 
  # Running web at 1:Free ($0/mo), worker at 1:Free ($0/mo)
  #
  # $ heroku ps:tier hobby
  # Changing dynos... done, now running web at 1:Hobby ($9/mo), worker at 1:Hobby ($9/mo)
  #
  # $ heroku ps:scale web=2
  # Scaling dynos... failed
  # !    Cannot scale to more than 1 Hobby size dynos per process type.
  #
  # $ heroku ps:tier production
  # Changing dynos... done, now running web at 1:Production ($30/mo), worker at 1:Production ($30/mo)
  #
  # $ heroku ps:scale web=2
  # Scaling dynos... done, now running web at 2:Production
  # 
  # $ heroku ps:tier hobby
  # Changing dynos... done, now running web at 1:Hobby ($9/mo), worker at 1:Hobby ($9/mo)
  
  def tier
    app
    tier_name = shift_argument.downcase
    validate_arguments!

    tiers = PROCESS_TIERS.reject { |t| t["tier"] == "legacy" }
    tier_names = tiers.map { |t| t["tier"] }

    unless api.get_feature("new-dyno-sizes", app).body["enabled"]
      raise Heroku::Command::CommandFailed.new("Cannot change process tier on this app.")
    end

    if !tier_names.include? tier_name
      raise Heroku::Command::CommandFailed.new("No such process tier as #{tier_name}. Available process tiers are #{tier_names.join(", ")}.")
    end

    # get formation
    resp = api.request(
      :expects => 200,
      :method  => :get,
      :path    => "/apps/#{app}/formation",
      :headers => {
        "Accept"       => "application/vnd.heroku+json; version=3",
        "Content-Type" => "application/json"
      }
    )

    formation = resp.body

    if tier_name == nil
      puts "DETECTING TIER"
      return
    end

    tier = tiers.detect { |t| t["tier"] == tier_name }

    # validate max_processes    
    if tier["max_processes"] && tier["max_processes"] < formation.map { |p| p["quantity"] }.inject(:+)
      raise Heroku::Command::CommandFailed.new("Cannot change process tier to #{tier_name}. App currently has more than #{tier['max_processes']} process types.")
    end

    # if free or hobby, first scale to max_scale
    if ["free", "hobby"].include? tier_name
      # TODO: Fix size+scale bug in API and remove this extra action
      if tier["max_scale"] && tier["max_scale"] < formation.map { |p| p["quantity"] }.max
        changes = formation.map { |p| 
          { 
            "process"   => p["type"],
            "quantity"  => p["quantity"] == 0 ? 0 : 1
          }
        }

        action("Changing process tier to #{tier_name} by scaling dynos") do
          resp = api.request(
            :expects => 200,
            :method  => :patch,
            :path    => "/apps/#{app}/formation",
            :body    => json_encode("updates" => changes),
            :headers => {
              "Accept"       => "application/vnd.heroku+json; version=3",
              "Content-Type" => "application/json"
            }
          )
        end
      end

      changes = formation.map { |p| 
        { 
          "process" => p["type"], 
          "size" => tier_name, 
        }
      }

    elsif tier_name == "production"
      changes = formation.map { |p| 
        { 
          "process"   => p["type"], 
          "size"      => p["size"] == "PX" ? "PX" : "production", 
        }
      }
    end    

    action("Changing process tier to #{tier_name} by resizing and restarting dynos") do
      resp = api.request(
        :expects => 200,
        :method  => :patch,
        :path    => "/apps/#{app}/formation",
        :body    => json_encode("updates" => changes),
        :headers => {
          "Accept"       => "application/vnd.heroku+json; version=3",
          "Content-Type" => "application/json"
        }
      )
    end
  end
end