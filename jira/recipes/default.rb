#
# Cookbook Name:: jira
# Recipe:: default
#
# Copyright 2008-2009, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Manual Steps!
#
# MySQL:
#
#   create database jiradb character set utf8;
#   grant all privileges on jiradb.* to '$jira_user'@'localhost' identified by '$jira_password';
#   flush privileges;

include_recipe "runit"
include_recipe "java"
include_recipe "apache2"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_http"
include_recipe "apache2::mod_ssl"

service "jira" do
  supports :restart => true, :status => true
  action :nothing
end

jira_major_version = node[:jira][:version].match(/^.*-(\d+)(\.\d+)*$/)[1].to_i  

unless FileTest.exists?(node[:jira][:install_path])
  remote_file "jira" do
    path "/tmp/jira.tar.gz"
    source "http://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-#{node[:jira][:version]}-standalone.tar.gz"
  end
  
  bash "untar-jira" do
    code "(cd /tmp; tar zxvf /tmp/jira.tar.gz)"
  end
  
  bash "install-jira" do
    code "mv /tmp/atlassian-jira-#{node[:jira][:version]}-standalone #{node[:jira][:install_path]}"
  end
  if node[:jira][:database] == "mysql" and jira_major_version < 4
    remote_file "mysql-connector" do
      path "/tmp/mysql-connector.tar.gz"
      source "http://downloads.mysql.com/archives/mysql-connector-java-5.1/mysql-connector-java-5.1.6.tar.gz"
    end
  
    bash "untar-mysql-connector" do
      code "(cd /tmp; tar zxvf /tmp/mysql-connector.tar.gz)"
    end
  
    bash "install-mysql-connector" do
      code "cp /tmp/mysql-connector-java-5.1.6/mysql-connector-java-5.1.6-bin.jar #{node[:jira][:install_path]}/common/lib"
    end
  end
end

subdirs = ['', '/conf', '/logs', '/work']
if jira_major_version >= 4
  subdirs.push(*['/data', '/export', '/log', '/plugins', '/caches', '/tmp', '/temp'])
end

subdirs.each do |dir|
  directory "#{node[:jira][:install_path]}#{dir}" do
    owner node[:jira][:run_user]
  end
end

remote_file "#{node[:jira][:install_path]}/bin/startup.sh" do
  source "startup.sh"
  mode 0755
  notifies :restart, resources(:service => "jira")
end
  
remote_file "#{node[:jira][:install_path]}/bin/catalina.sh" do
  source "catalina.sh"
  mode 0755
  notifies :restart, resources(:service => "jira")
end

template "#{node[:jira][:install_path]}/conf/server.xml" do
  if jira_major_version < 4
    source "server.xml.erb"
  else
    source "server.xml.4.x.x.erb"
  end
  mode 0755
  notifies :restart, resources(:service => "jira")
end
  
template "#{node[:jira][:install_path]}/atlassian-jira/WEB-INF/classes/entityengine.xml" do
  source "entityengine.xml.erb"
  mode 0755
  notifies :restart, resources(:service => "jira")
end

runit_service "jira"

template "#{node[:apache][:dir]}/sites-available/jira.conf" do
  source "apache.conf.erb"
  mode 0644
  variables({
    :port => 80
  })
  notifies :restart, resources(:service => "apache2")
end

template "#{node[:apache][:dir]}/sites-available/jira-require-ssl.conf" do
  source "apache.require-ssl-conf.erb"
  mode 0644
  variables({
    :port => 80
  })
  notifies :restart, resources(:service => "apache2")
end

template "#{node[:apache][:dir]}/sites-available/jira-ssl.conf" do
  source "apache.conf.erb"
  mode 0644
  variables({
    :port => 443,
    :ssl_certificate_path => node[:jira][:ssl_certificate_path],
    :ssl_key_path => node[:jira][:ssl_key_path]
  })
  notifies :restart, resources(:service => "apache2")
end

apache_site "jira.conf" do
  enable !node[:jira][:require_ssl]
end

apache_site "jira-require-ssl.conf" do
  enable node[:jira][:require_ssl]
end

apache_site "jira-ssl.conf" do
  enable node[:jira][:enable_ssl]
end
