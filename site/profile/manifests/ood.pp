# Initializes Open OnDemand node and prepares web frontend
# for cluster user access.

class profile::ood::web {
  include profile::freeipa

  # Create the HTTP service principal in FreeIPA and generate the interal SSL cert.
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $fqdn = "${lookup('terraform.tag_ip.ood.0')}.int.${ipa_domain}"
  $service_name = "HTTP/${fqdn}"
  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  $getcert_command = @("EOT")
    kinit_wrapper ipa service-add "${service_name}" && \
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
      File['/usr/bin/kinit_wrapper'],
      Exec['ipa-install'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  include openondemand

  $base_dn = join(split($ipa_domain, '[.]').map |$dc| { "dc=${dc}" }, ',')
  $dex_ldap_connector = {
    type   => 'ldap',
    id     => 'ldap',
    name   => 'LDAP',
    config => {
      host               => "%{lookup('profile::reverse_proxy::subdomains.ipa')}:636",
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

  class { 'openondemand::dex_config':
    connectors => [$dex_ldap_connector]
  }
}

class profile::ood::node {
  include epel

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
