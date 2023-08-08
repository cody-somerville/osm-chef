#
# Cookbook:: civicrm
# Recipe:: default
#
# Copyright:: 2011, OpenStreetMap Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "wordpress"
include_recipe "mysql"

package %w[
  php-xml
  php-curl
  rsync
  wkhtmltopdf
  php-bcmath
  php-intl
]

cache_dir = Chef::Config[:file_cache_path]

passwords = data_bag_item("civicrm-staging", "passwords")
wp2fa_encrypt_keys = data_bag_item("civicrm-staging", "wp2fa_encrypt_keys")

database_password = passwords["database"]
site_key = passwords["site_key"]
cred_keys = passwords["cred_keys"]
sign_keys = passwords["sign_keys"]

mysql_user "civicrm-staging@localhost" do
  password database_password
end

mysql_database "civicrm-staging" do
  permissions "civicrm-staging@localhost" => :all
end

wordpress_site "join-staging.osmfoundation.org" do
  aliases "crm-staging.osmfoundation.org"
  database_name "civicrm-staging"
  database_user "civicrm-staging"
  database_password database_password
  wp2fa_encrypt_key wp2fa_encrypt_keys["key"]
  fpm_prometheus_port 11301
end

wordpress_theme "osmblog-wp-theme" do
  site "join-staging.osmfoundation.org"
  repository "https://github.com/osmfoundation/osmblog-wp-theme.git"
end

wordpress_plugin "registration-honeypot" do
  site "join-staging.osmfoundation.org"
end

wordpress_plugin "contact-form-7" do
  site "join-staging.osmfoundation.org"
end

wordpress_plugin "civicrm-admin-utilities" do
  site "join-staging.osmfoundation.org"
end

civicrm_version = node[:civicrm_staging][:version]
civicrm_directory = "/srv/join-staging.osmfoundation.org/wp-content/plugins/civicrm"

directory "/opt/civicrm-staging-#{civicrm_version}" do
  owner "wordpress"
  group "wordpress"
  mode "755"
end

remote_file "#{cache_dir}/civicrm-#{civicrm_version}-wordpress.zip" do
  action :create_if_missing
  source "https://download.civicrm.org/civicrm-#{civicrm_version}-wordpress.zip"
  owner "wordpress"
  group "wordpress"
  mode "644"
  backup false
end

remote_file "#{cache_dir}/civicrm-#{civicrm_version}-l10n.tar.gz" do
  action :create_if_missing
  source "https://download.civicrm.org/civicrm-#{civicrm_version}-l10n.tar.gz"
  owner "wordpress"
  group "wordpress"
  mode "644"
  backup false
end

archive_file "#{cache_dir}/civicrm-#{civicrm_version}-wordpress.zip" do
  action :nothing
  destination "/opt/civicrm-staging-#{civicrm_version}"
  overwrite true
  owner "wordpress"
  group "wordpress"
  subscribes :extract, "remote_file[#{cache_dir}/civicrm-#{civicrm_version}-wordpress.zip]", :immediately
end

archive_file "#{cache_dir}/civicrm-#{civicrm_version}-l10n.tar.gz" do
  action :nothing
  destination "/opt/civicrm-staging-#{civicrm_version}/civicrm"
  overwrite true
  owner "wordpress"
  group "wordpress"
  subscribes :extract, "remote_file[#{cache_dir}/civicrm-#{civicrm_version}-l10n.tar.gz]", :immediately
end

execute "/opt/civicrm-staging-#{civicrm_version}/civicrm" do
  action :nothing
  command "rsync --archive --delete /opt/civicrm-staging-#{civicrm_version}/civicrm/ #{civicrm_directory}"
  user "wordpress"
  group "wordpress"
  subscribes :run, "archive_file[#{cache_dir}/civicrm-#{civicrm_version}-wordpress.zip]", :immediately
  subscribes :run, "archive_file[#{cache_dir}/civicrm-#{civicrm_version}-l10n.tar.gz]", :immediately
end

directory "/srv/join-staging.osmfoundation.org/wp-content/uploads" do
  owner "www-data"
  group "www-data"
  mode "755"
end

extensions_directory = "/srv/join-staging.osmfoundation.org/wp-content/plugins/civicrm-extensions"

directory extensions_directory do
  owner "wordpress"
  group "wordpress"
  mode "755"
end

node[:civicrm_staging][:extensions].each_value do |details|
  git "#{extensions_directory}/#{details[:name]}" do
    action :sync
    repository details[:repository]
    revision details[:revision]
    user "wordpress"
    group "wordpress"
  end
end

settings = edit_file "#{civicrm_directory}/civicrm/templates/CRM/common/civicrm.settings.php.template" do |line|
  line.gsub!(/%%cms%%/, "WordPress")
  line.gsub!(/%%CMSdbUser%%/, "civicrm-staging")
  line.gsub!(/%%CMSdbPass%%/, database_password)
  line.gsub!(/%%CMSdbHost%%/, "localhost")
  line.gsub!(/%%CMSdbName%%/, "civicrm-staging")
  line.gsub!(/%%dbUser%%/, "civicrm-staging")
  line.gsub!(/%%dbPass%%/, database_password)
  line.gsub!(/%%dbHost%%/, "localhost")
  line.gsub!(/%%dbName%%/, "civicrm-staging")
  line.gsub!(/%%crmRoot%%/, "#{civicrm_directory}/civicrm/")
  line.gsub!(/%%templateCompileDir%%/, "/srv/join-staging.osmfoundation.org/wp-content/uploads/civicrm/templates_c/")
  line.gsub!(/%%baseURL%%/, "http://join-staging.osmfoundation.org/")
  line.gsub!(/%%siteKey%%/, site_key)
  line.gsub!(/%%credKeys%%/, cred_keys)
  line.gsub!(/%%signKeys%%/, sign_keys)
  line.gsub!(%r{// *define\('CIVICRM_CMSDIR', '/path/to/install/root/'\);}, "define('CIVICRM_CMSDIR', '/srv/join-staging.osmfoundation.org');")

  line
end

file "#{civicrm_directory}/civicrm.settings.php" do
  owner "wordpress"
  group "wordpress"
  mode "644"
  content settings
end

# systemd_service "osmf-crm-staging-jobs" do
#   description "Run CRM staging jobs"
#   exec_start "/usr/bin/php #{civicrm_directory}/civicrm/bin/cli.php -s join-staging.osmfoundation.org -u batch -p \"#{passwords['batch']}\" -e Job -a execute"
#   user "www-data"
#   sandbox :enable_network => true
#   memory_deny_write_execute false
#   restrict_address_families "AF_UNIX"
#   read_write_paths "/srv/join-staging.osmfoundation.org/wp-content/uploads/civicrm"
# end

# systemd_timer "osmf-crm-staging-jobs" do
#   description "Run CRM staging jobs"
#   on_boot_sec "15m"
#   on_unit_inactive_sec "15m"
# end

# service "osmf-crm-jobs-staging.timer" do
#   action [:enable, :start]
# end

# template "/etc/cron.daily/osmf-crm-staging-backup" do
#   source "backup.cron.erb"
#   owner "root"
#   group "root"
#   mode "750"
#   variables :passwords => passwords
# end