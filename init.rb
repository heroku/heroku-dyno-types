PROCESS_TIERS = JSON.parse <<EOF
[
  { "tier": "free",        "max_scale": 1,   "max_processes": 2,    "cost": { "Free": 0 } },
  { "tier": "hobby",       "max_scale": 1,   "max_processes": null, "cost": { "Hobby": 700 } },
  { "tier": "production",  "max_scale": 100, "max_processes": null, "cost": { "Standard-1X": 2500, "Standard-2X": 5000, "Performance": 50000 } },
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
  # ps:type [TYPE | DYNO=TYPE [DYNO=TYPE ...]]
  #
  # manage dyno types
  #
  # called with no arguments shows the current dyno type
  #
  # called with one argument sets the type
  # where type is one of traditional|free|hobby|basic|production
  #
  # called with 1..n DYNO=TYPE arguments sets the type per dyno
  # this is only available when the app is on production and performance
  #
  def type
    if args.any?{|arg| arg =~ /=/}
      _original_resize
      return
    end

    app
    process_tier = shift_argument.downcase
    validate_arguments!

    # get or update app.process_tier
    app_resp = process_tier.nil? ? edge_app_info : change_dyno_type(process_tier)

    # get, calculate and display app process type costs
    formation_resp = edge_app_formation

    display_dyno_type_and_costs(app_resp, formation_resp)
  end

  alias_method :resize, :type

  private

  def change_dyno_type(process_tier)
    print "Changing dyno type... "

    app_resp = api.request(
      :method  => :patch,
      :path    => "/apps/#{app}",
      :body    => json_encode("process_tier" => process_tier),
      :headers => {
        "Accept"       => "application/vnd.heroku+json; version=edge",
        "Content-Type" => "application/json"
      }
    )

    if app_resp.status != 200
      puts "failed"
      error app_resp.body["message"] + " Please use `heroku ps:scale` to change process size and scale."
    end

    puts "done."

    return app_resp
  end

  def display_dyno_type_and_costs(app_resp, formation_resp)
    tier_info = PROCESS_TIERS.detect { |t| t["tier"] == app_resp.body["process_tier"] }

    puts "Dyno type: #{app_resp.body["process_tier"]}"

    formation = formation_resp.body.reject {|ps| ps['quantity'] < 1}
    ps_costs = formation.map do |ps|
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

  def edge_app_info
    api.request(
      :expects => 200,
      :method  => :get,
      :path    => "/apps/#{app}",
      :headers => {
        "Accept"       => "application/vnd.heroku+json; version=edge",
        "Content-Type" => "application/json"
      }
    )
  end

  def edge_app_formation
    api.request(
      :expects => 200,
      :method  => :get,
      :path    => "/apps/#{app}/formation",
      :headers => {
        "Accept"       => "application/vnd.heroku+json; version=3",
        "Content-Type" => "application/json"
      }
    )
  end


  def _original_resize
    app
    change_map = {}

    changes = args.map do |arg|
      if arg =~ /^([a-zA-Z0-9_]+)=([\w-]+)$/
        change_map[$1] = $2
        { "process" => $1, "size" => $2 }
      end
    end.compact

    if changes.empty?
      message = [
          "Usage: heroku dyno:type DYNO1=1X|2X|PX [DYNO2=1X|2X|PX ...]",
          "Must specify DYNO and TYPE to resize."
      ]
      error(message.join("\n"))
    end

    resp = nil
    action("Resizing and restarting the specified dynos") do
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

    resp.body.select {|p| change_map.key?(p['type']) }.each do |p|
      size = p["size"]
      price = if size.to_i > 0
                sprintf("%.2f", 0.05 * size.to_i)
              else
                sprintf("%.2f", PRICES[size])
              end
      display "#{p["type"]} dynos now #{size} ($#{price}/dyno-hour)"
    end
  end
end


%w[type restart scale stop].each do |cmd|
  Heroku::Command::Base.alias_command "dyno:#{cmd}", "ps:#{cmd}"
end

