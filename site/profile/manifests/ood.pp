# Initializes Open OnDemand node and prepares web frontend
# for cluster user access.

class profile::ood::web {
  package { 'mod_lua':
    ensure => 'installed',
  }

  file { "/usr/bin/kinit_wrapper":
    source  => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode    => '0755',
  }

  # Create the HTTP service principal in FreeIPA and generate the internal SSL cert.
  $reverse_zone = profile::getreversezone()
  $clean_zone = chop($reverse_zone)
  $ptr_record = profile::getptrrecord()
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $service_name = "HTTP/${fqdn}"
  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  
  $service_register_script = @("EOF")
    api.Command.batch(
      { 'method': 'dnsrecord_add', 'params': [['${clean_zone}', '${ptr_record}'], {'ptrrecord' : '${fqdn}.'}]},
      { 'method': 'service_add', 'params': [['${service_name}'], {}]},
    )
    | EOF

  file { "/etc/ipa/ipa_register_service.py":
    content => $service_register_script,
    require => Exec['ipa-install'],
  }

  exec { 'ipa_register_service':
    command     => 'kinit_wrapper ipa console /etc/ipa/ipa_register_service.py',
    unless => "kinit_wrapper ipa service-show '${service_name}' >/dev/null 2>&1",
    require     => [
      File['/etc/ipa/ipa_register_service.py'],
      File['/usr/bin/kinit_wrapper'],
      Exec['ipa-install'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }
  
  $getcert_command = @("EOT")
    kinit_wrapper ipa-getcert request -r \
    -f /etc/pki/tls/certs/httpd.crt \
    -k /etc/pki/tls/private/httpd.key \
    -K "${service_name}" \
    -D "${fqdn}" \
    -A "${facts['networking']['ip']}"
    | EOT

  exec { 'ood_getcert':
    command     => $getcert_command,
    creates     => '/etc/pki/tls/certs/httpd.crt',
    require     => [
      File['/usr/bin/kinit_wrapper'],
      Exec['ipa-install'],
      Exec['ipa_register_service'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }
  
  $generated_passphrase = Sensitive(stdlib::fqdn_rand_string(32))
  $base_dn = join(split($ipa_domain, '[.]').map |$dc| { "dc=${dc}" }, ',')
  $dex_ldap_connector = {
    type   => 'ldap',
    id     => 'ldap',
    name   => 'LDAP',
    config => {
      host               => "${lookup('profile::reverse_proxy::subdomains.ipa')}:636",
      insecureSkipVerify => true,
      bindDN             => "uid=admin,cn=users,cn=accounts,${base_dn}",
      bindPW             => "${ipa_passwd}",
      userSearch => {
        baseDN                => "cn=users,cn=accounts,${base_dn}",
        filter                => '(objectClass=posixAccount)',
        username              => 'uid',
        idAttr                => 'uid',
        emailAttr             => 'mail',
        nameAttr              => 'gecos',
        preferredUsernameAttr => 'uid',
      },
      groupSearch => {
        baseDN      => "ou=Groups,${base_dn}",
        filter      => '(objectClass=posixGroup)',
        userMatches => [
            {
              userAttr  => 'DN',
              groupAttr => 'member',
            },
        ],
        nameAttr => 'cn',
      },
    },
  }

  class { 'openondemand':
    dex_config => {
      'connectors' => [$dex_ldap_connector],
    },
    oidc_crypto_passphrase => $generated_passphrase.unwrap,
    host_regex => join(['[\w.-]+\.',regsubst(lookup('terraform.data.domain_name'), '\.', '\\.', 'G')])
  }

  exec { 'wait_for_httpd_cert':
    command => '/usr/bin/test -s /etc/pki/tls/certs/httpd.crt',
    tries => 24,
    try_sleep => 5,
    refreshonly => true,
    require => Exec['ood_getcert'],
    path => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }
 
  Exec['ood_getcert']
    ~> Exec['wait_for_httpd_cert']
    -> File['/etc/ood/config/ood_portal.yml']
}

class profile::ood::node {
  include epel

  package { '@base-x':
    ensure => 'installed',
  }

  $xfce_packages = [
    'thunar',
    'xfce4-panel',
    'xfce4-session',
    'xfce4-settings',
    'xfconf',
    'xfdesktop',
    'xfwm4',
    'xfce4-terminal'
  ]

  package { $xfce_packages:
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  package { 'nmap-ncat':
    ensure => 'installed',
  }

  yumrepo { 'turbovnc-repo':
    ensure        => 'present',
    descr         => 'TurboVNC official RPMs',
    baseurl       => 'https://packagecloud.io/dcommander/turbovnc/rpm_any/rpm_any/$basearch',
    repo_gpgcheck => 1,
    gpgcheck      => 1,
    gpgkey        => 'https://packagecloud.io/dcommander/turbovnc/gpgkey',
    enabled       => 1,
  }

  package { 'turbovnc':
    ensure  => 'installed',
    require => [Yumrepo['epel'], Yumrepo['turbovnc-repo']],
  }

  package { 'python3-websockify':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }
}
