# Initializes Open OnDemand node and prepares web frontend
# for cluster user access.

# Provide Slurm ClusterName for templating files
class profile::ood (
  String[1, 40] $cluster_name,
) {

  stdlib::ensure_packages(['wget'], { ensure => 'present' })
  stdlib::yumrepo(['crb'], { ensure => present, enabled => true})
  stdlib::ensure_packages(['ruby'], { ensure => '3.3', provider => 'dnfmodule', enableonly => true, require => Yumrepo['epel'] })
  stdlib::ensure_packages(['nodejs'], { ensure => '22', provider => 'dnfmodule', enableonly => true, require => Yumrepo['epel'] })
  stdlib::ensure_packages() 





}
