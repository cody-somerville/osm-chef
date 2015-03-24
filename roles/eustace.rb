name "eustace"
description "Master role applied to eustace"

default_attributes(
  :chef => {
    :client => {
      :version => "12.1.2-1"
    }
  },
  :networking => {
    :interfaces => {
      :internal_ipv4 => {
        :interface => "eth0",
        :role => :internal,
        :family => :inet,
        :address => "10.0.0.9"
      },
      :external_ipv4 => {
        :interface => "eth1",
        :role => :external,
        :family => :inet,
        :address => "128.40.45.197"
      }
    }
  }
)

run_list(
  "role[ucl-wolfson]",
  "role[hp-g6]",
  "role[piwik]"
)
