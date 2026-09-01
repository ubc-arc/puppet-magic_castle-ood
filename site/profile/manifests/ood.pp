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

  # Create the HTTP service principal in FreeIPA and generate the interal SSL cert.
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $fqdn = "${lookup('terraform.tag_ip.ood.0')}.int.${ipa_domain}"
  $service_name = "HTTP/${fqdn}"
  $service_register_script = @("EOF")
    api.Command.batch(
      { 'method': 'service_add',           'params': [['${service_name}'], {}]},
      { 'method': 'service_add_principal', 'params': [['${service_name}', 'ood/ood'], {}]},
    )
    |EOF

  file { '/etc/ood/ood_ipa_service_register.py':
    content => $service_register_script,
    require => [
      Package['ondemand']
    ],
  }

  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  $getcert_command = @("EOT")
    kinit_wrapper ipa console /etc/ood/ood_ipa_service_register.py && \
    kinit_wrapper ipa-getcert request \
    -f /etc/pki/tls/certs/httpd.crt \
    -k /etc/pki/tls/private/httpd.key \
    -K '${service_name}' \
    -D '${fqdn}'
    |EOT
  exec { 'ood_getcert':
    command     => $getcert_command,
    creates     => [
      '/etc/pki/tls/certs/httpd.crt',
      '/etc/pki/tls/private/httpd.key'
    ],
    require     => [
      File['/etc/ood'],
      File['kinit_wrapper'],
      Exec['ipa-install'],
    ],
    subscribe   => File['/etc/ood/ood_ipa_service_register.py'],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }
}
