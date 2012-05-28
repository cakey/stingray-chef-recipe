node.default[:stingray][:version] = "8.2a1"
node.default[:stingray][:platform] = "Linux"
node.default[:stingray][:installpath] = "/space/demo10"
node.default[:stingray][:full_hostname] = "hostname"
node.default[:stingray][:port] = "9070"
node.default[:stingray][:password] = "password"
#node.default[:stingray][:config_tar] = "config_3737new.tar"
node.default[:stingray][:vservers] = {
            "webapp_vs" => 
                    {"port" => 5556, "pool" => "webapps"},
            "db_vs"    => 
                    {"port" => 5557, "pool" => "dbs"},
            "cache_vs" => 
                    {"port" => 5558, "pool" => "caches"}
            }
node.default[:stingray][:pools] = {
            "webapps" => 
                    {"nodes" => [
                                    "hostname-1:80",
                                    "hostname-2:80"
                                ]
                    },
            "dbs" => 
                    {"nodes" => [
                                    "hostname-3:80",
                                    "hostname-4:80"
                                ]
                    },
            "cache" => {"nodes" => ["hostname-5:80"]}}



