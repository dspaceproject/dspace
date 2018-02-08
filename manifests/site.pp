# Definition: dspace::site
#
# Each time this is called, the following happens:
#  - DSpace source is pulled down from GitHub
#  - DSpace Maven build process is run (if it has not yet been run)
#  - DSpace Ant installation process is run (if it has not yet been run)
#
# Tested on:
# - Ubuntu 16.04
#
# Parameters:
# - $owner              => OS User who should own DSpace instance
# - $group              => Group who should own DSpace instance.
# - $src_dir            => Location where DSpace source should be kept
# - $install_dir        => Location where DSpace instance should be installed (defaults to $name)
# - $git_repo           => Git repository to pull DSpace source from. Defaults to DSpace/DSpace in GitHub
# - $git_branch         => Git branch to build DSpace from. Defaults to "master".
# - $mvn_params         => Any build params passed to Maven. Defaults to "-Denv=custom" which tells Maven to use the custom.properties file.
# - $ant_installer_dir  => Name of directory where the Ant installer is built to (via Maven).
# - $admin_firstname    => First Name of the created default DSpace Administrator account.
# - $admin_lastname     => Last Name of the created default DSpace Administrator account.
# - $admin_email        => Email of the created default DSpace Administrator account.
# - $admin_passwd       => Initial Password of the created default DSpace Administrator account.
# - $admin_language     => Language of the created default DSpace Administrator account.
# - $handle_prefix      => Handle Prefix to use for this site (default = 123456789)
# - $local_config_source=> Can be used to override the default local.cfg with one of your own
#                          Specify a valid Puppet "source", which could be a file location, HTTP URL, etc. 
# - $ensure => Whether to ensure DSpace instance is created ('present', default value) or deleted ('absent')
#
# Sample Usage:
# dspace::site { '/dspace':
#    owner      => "dspace",
#    git_branch => "master",
# }
#
define dspace::site ($owner             = $dspace::owner,
                        $group             = $dspace::group,
                        $site_name         = "${title}",
                        $install_dir       = "/efs/${site_name}",
                        $src_dir           = "/efs/${site_name}/dspace-src",
		        $username          = "${owner}",
			$tomcat_name       = undef,
			            
			$source_url        = undef,
 
			$catalina_base     = undef,
                        $catalina_home     = undef,
			$tomcat_ajp_port   = $dspace::tomcat_ajp_port,
	             	$port              = $dspace::tomcat_port,
			$tomcat_port       = undef,
 			$tomcat_shutdown_port = undef,
						
                        $git_repo          = $dspace::git_repo,
                        $git_branch        = undef,
                        $mvn_params        = $dspace::mvn_params,
                        $ant_installer_dir = $dspace::installer_dir_name,
                        $admin_firstname   = $dspace::admin_firstname,
                        $admin_lastname    = $dspace::admin_lastname,
                        $admin_email       = $dspace::admin_email,
                        $admin_passwd      = $dspace::admin_passwd,
                        $admin_language    = $dspace::admin_language,
                        $admin1_firstname   = undef,
                        $admin1_lastname    = undef,
                        $admin1_email       = undef,
                        $admin1_passwd      = undef,
                        $admin1_language    = undef,
                        $db_name           = $dspace::db_name,
                        $db_port           = $dspace::db_port,
                        $db_user           = $dspace::db_owner,
                        $db_passwd         = $dspace::db_owner_passwd,
                        $db_endpoint       = undef,
                        $handle_prefix     = $dspace::handle_prefix,
                        $local_config_source = undef,
                        $ensure            = present)
{
  # Full path to Ant Installer (based on passed in $src_dir)
    $ant_installer_path = "${src_dir}/dspace/target/${ant_installer_dir}"
 
	
  ######################
  # . Create Acccount owner . #
  #######################
  
  dspace::owner { "${owner}":
  gid    => $owner,  # Primary OS group name / ID
  groups => root, # Additional OS groups
  sudoer => true,  # Whether to add acct as a sudoer
  }
  
  
  
->	

    # ensure that the install_dir exists, and has proper permissions
    file { "${install_dir}":
       ensure => "directory",
      owner  => $owner,
     group  => $group,
    mode   => '0700',
    }

->

    ### BEGIN clone of DSpace from GitHub to ~/dspace-src (this is a bit of a strange way to ckeck out, we do it this
    ### way to support cases where src_dir already exists)

    # if the src_dir folder does not yet exist, create it
    file { "${src_dir}":
        ensure => directory,
        owner  => $owner,
        group  => $group,
        mode   => '0700',
    }

->
exec { 'create database':
   environment => ["PGPASSWORD=${db_passwd}"],
   command => "psql --host=${db_endpoint} --port=5432  --username=${db_user} --command='CREATE DATABASE ${db_name}'",
   path => [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
 }
->


    exec { "Cloning DSpace source code into ${src_dir}":
        command   => "git init && git remote add origin ${git_repo} && git fetch --all && git checkout -B dspace-5_x origin/dspace-5_x",
        path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
	creates   => "${src_dir}/.git",
        #user      => $owner,
        cwd       => $src_dir, # run command from this directory
        logoutput => true,
        tries     => 4,    # try 4 times
        timeout   => 1200, # set a 20 min timeout. DSpace source is big which could be slow on some connections
    }


    ### END clone of DSpace

->

    # Checkout the specified branch
    exec { "Checkout branch ${git_branch}" :
       command => "git checkout ${git_branch}",
       path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
       cwd     => $src_dir, # run command from this directory
       user    => $owner,
       # Only perform this checkout if the branch EXISTS and it is NOT currently checked out (if checked out it will have '*' next to it in the branch listing)
       onlyif  => "git branch -a | grep -w '${git_branch}' && git branch | grep '^\\*' | grep -v '^\\* ${git_branch}\$'",
    }

->

exec { "Delete default build.properties in ${src_dir}":
    command   => "rm build.properties",
    path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
    cwd       => "${src_dir}", # Run command from this directory
    user      => $owner,
    #subscribe => File["${src_dir}/dspace/config/local.cfg"], # If local.cfg changes, rebuildi
    #refreshonly => true,  # Only run if local.cfg changes
    #timeout   => 18000, # Disable timeout. This build takes a while!
    #logoutput => true,    # Send stdout to puppet log file (if any)
    #notify    => Exec["Install DSpace to ${install_dir}"],  # Notify installation to run
    require => Exec["Checkout branch ${git_branch}"],
    before  => Exec["Build DSpace installer in ${src_dir}"],
}

->
   # Create a 'custom.properties' file which will be used by older versions of DSpace to build the DSpace installer
   # (INSTEAD OF the default 'build.properties' file that DSpace normally uses)
   # kept for backwards compatibility, no longer needed for DSpace 6+
   file { "${src_dir}/build.properties":
     ensure  => file,
     owner   => $owner,
     group   => $group,
     mode    => '0644',
     content => template("dspace/custom.properties.erb"),
     require => Exec["Checkout branch ${git_branch}"],
     before  => Exec["Build DSpace installer in ${src_dir}"],
  }



   # Decide whether to initialize local.cfg (required for DSpace 6+) from a provided file ($local_source_config)
   # Or from the default template (local.cfg.erb)
   if $local_config_source {
     # Initialize local.cfg from provided source file
     file { "${src_dir}/dspace/config/local.cfg":
       ensure  => file,
       owner   => $owner,
       group   => $group,
       mode    => '0644',
       source  => $local_config_source,
       require => Exec["Checkout branch ${git_branch}"],
       before  => Exec["Build DSpace installer in ${src_dir}"],
     }
   }
   else {
     # Create a 'local.cfg' file from our default template
     file { "${src_dir}/dspace/config/local.cfg":
       ensure  => file,
       owner   => $owner,
       group   => $group,
       mode    => '0644',
       content => template("dspace/local.cfg.erb"),
       require => Exec["Checkout branch ${git_branch}"],
       before  => Exec["Build DSpace installer in ${src_dir}"],
     }

   }




   # Build DSpace installer.
   # (NOTE: by default, $mvn_params='-Denv=custom', which tells Maven to use the custom.properties file created above)
   exec { "Build DSpace installer in ${src_dir}":
     command   => "mvn -U package",
     path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
     cwd       => "${src_dir}", # Run command from this directory
#     user      => $owner,
     subscribe => File["${src_dir}/dspace/config/local.cfg"], # If local.cfg changes, rebuildi
     refreshonly => true,  # Only run if local.cfg changes
     timeout   => 180000, # Disable timeout. This build takes a while!
     require => Class['dspace'],
     logoutput => true,    # Send stdout to puppet log file (if any)
     notify    => Exec["Install DSpace to ${install_dir}"],  # Notify installation to run
   }

   # Install DSpace (via Ant)
   exec { "Install DSpace to ${install_dir}":
     # If DSpace installed, this is an update. Otherwise a fresh_install
     #command   => "if [ -f ${install_dir}/bin/dspace ]; then ant update; else ant fresh_install; fi",
     command  => "ant fresh_install",
     path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
     provider  => shell,   # Run as a shell command
     cwd       => $ant_installer_path,    # Run command from this directory
    # user      => $owner,
     logoutput => true,    # Send stdout to puppet log file (if any)
     refreshonly => true,  # Only run when triggered (by build)
   }

   # Create initial administrator (if specified)
 if $admin_email and $admin_passwd and $admin_firstname and $admin_lastname and $admin_language and $admin1_email and $admin1_passwd and $admin1_firstname and $admin1_lastname and $admin1_language
   {
     exec { "Create DSpace Administrator":
       command   => "${install_dir}/bin/dspace create-administrator -e ${admin_email} -f ${admin_firstname} -l ${admin_lastname} -p ${admin_passwd} -c ${admin_language}",
       cwd       => $install_dir,
     #  user      => $owner,
       logoutput => true,
       require   => Exec["Install DSpace to ${install_dir}"],     

}
   }


 if $admin1_email and $admin1_passwd and $admin1_firstname and $admin1_lastname and $admin1_language
   {
     exec { "Create DSpace Administrator_2":
       command   => "${install_dir}/bin/dspace create-administrator -e ${admin1_email} -f ${admin1_firstname} -l ${admin1_lastname} -p ${admin1_passwd} -c ${admin1_language}",
       cwd       => $install_dir,
       user      => $owner,
       logoutput => true,
       require   => Exec["Install DSpace to ${install_dir}"],

}
   }
  
 
####################Setup Tomcat#########################
#########################
  # Setup Tomcat Instance
  ##########################
  #Create a new Tomcat instance owned by this user
  
  
  tomcat::instance { $url :
           catalina_home => $catalina_home,
           source_url   => $source_url,
         }
         
-> 
  ######################################################
  #  SET/Change tomcat's server and HTTP/AJP connectors
  #######################################################
  tomcat::config::server { "${owner}":
   catalina_base => $catalina_base,
   port          => $tomcat_shutdown_port,
  }

  tomcat::config::server::connector { "${owner}-http":
   catalina_base         => $catalina_base,
   port                  => $tomcat_port,
   protocol              => 'HTTP/1.1',
   purge_connectors      => true,
   additional_attributes => {
    'redirectPort' => '8443'
   },
  }

  tomcat::config::server::connector { "${owner}-ajp":
   catalina_base         => $catalina_base,
   port                  => $tomcat_ajp_port,
   protocol              => 'AJP/1.3',
   purge_connectors      => true,
   additional_attributes => {
    'redirectPort' => '8443'
  },
  }
  
   #######################################
  # . Set Dspace WebApps on Tomcat .    #
  #######################################
 #Default 

 ->

 tomcat::config::server::context {"${title}":
        catalina_base => $catalina_base,
        context_ensure => 'present',
        doc_base => "/efs/${site_name}/webapps/xmlui",
        parent_host => "localhost",
        additional_attributes => {'path'=>'/'},
      }
  ->


 file { "${catalina_base}/webapps/ROOT/index.html":
     ensure  => file,
     owner   => $owner,
     group   => $group,
     mode    => '0644',
     content => template("dspace/index.html.erb"),
  }


->

file { "/etc/init.d/${tomcat_name}":
            ensure  => 'file',
            owner   => root,
            group   => root,
            content => template("dspace/tomcat.erb"),
            mode    => '+x',
         }

->            
 
 
 

exec { 'rc':
        command => "update-rc.d ${tomcat_name} defaults",
        path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
}

->


exec { 'start':
        command => "service ${tomcat_name} start",
        path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
}

->


exec { 'daemon-reload':
        command => "systemctl daemon-reload",
        path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
}
->
exec { 'restart':
        command => "service ${tomcat_name} restart",
        path =>  [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
}

 ->


 ####################################
  # Setup Apache Redirect to Tomcat  #
  ####################################
  notify { "The Hash values are: ${site_name}": }
         # Create a new Apache vhost (site) which will redirect (via AJP)
         # requests to the Tomcat instance created above.
         dspace::apache_site { $site_name :
           ensure           => present,
           tomcat_ajp_port  => $tomcat_ajp_port,
         }
}

