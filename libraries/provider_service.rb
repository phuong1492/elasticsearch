# Chef Provider for configuring an elasticsearch service in the init system
class ElasticsearchCookbook::ServiceProvider < Chef::Provider::LWRPBase
  provides :elasticsearch_service
  include ElasticsearchCookbook::Helpers

  def whyrun_supported?
    false
  end

  action :remove do
    raise "#{new_resource} remove not currently implemented"
  end

  action :configure do
    es_user = find_es_resource(run_context, :elasticsearch_user, new_resource)
    es_install = find_es_resource(run_context, :elasticsearch_install, new_resource)
    es_conf = find_es_resource(run_context, :elasticsearch_configure, new_resource)

    d_r = directory es_conf.path_pid[es_install.type] do
      owner es_user.username
      group es_user.groupname
      mode '0755'
      recursive true
      action :nothing
    end
    d_r.run_action(:create)
    new_resource.updated_by_last_action(true) if d_r.updated_by_last_action?

    # Create systemd unit file
    #
    systemd_unit_r = template "/etc/systemd/system/#{new_resource.service_name}.service" do
      source new_resource.systemd_source
      cookbook new_resource.systemd_cookbook
      owner 'root'
      group 'root'
      mode '0644'
      variables(
        program_name: new_resource.service_name,
        path_home: es_conf.path_home[es_install.type],
        path_conf: es_conf.path_conf[es_install.type],
        path_data: es_conf.path_data[es_install.type],
        path_logs: es_conf.path_logs[es_install.type],
        path_pid: es_conf.path_pid[es_install.type],
        es_user: es_user.username,
        es_group: es_user.groupname,
        default_dir: '/etc/sysconfig'
      )
      action :nothing
    end
    systemd_unit_r.run_action(:create)
    new_resource.updated_by_last_action(true) if systemd_unit_r.updated_by_last_action?

    # Reload systemd daemon
    #
    if systemd_unit_r.updated_by_last_action?
      reload_r = execute 'systemctl-daemon-reload' do
        command 'systemctl daemon-reload'
        action :nothing
      end
      reload_r.run_action(:run)
    end

    # flatten in an array here, in case the service_actions are a symbol vs. array
    [new_resource.service_actions].flatten.each do |act|
      passthrough_action(act)
    end
  end

  # Passthrough actions to service[service_name]
  #
  action :enable do
    passthrough_action(:enable)
  end

  action :disable do
    passthrough_action(:disable)
  end

  action :start do
    passthrough_action(:start)
  end

  action :stop do
    passthrough_action(:stop)
  end

  action :restart do
    passthrough_action(:restart)
  end

  action :status do
    passthrough_action(:status)
  end

  def passthrough_action(action)
    svc_r = lookup_service_resource
    svc_r.run_action(action)
    new_resource.updated_by_last_action(true) if svc_r.updated_by_last_action?
  end

  def lookup_service_resource
    rc = run_context.resource_collection
    rc.find("service[#{new_resource.service_name}]")
  rescue
    service new_resource.service_name do
      supports :status => true, :restart => true
      action :nothing
    end
  end
end
