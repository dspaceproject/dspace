class profile{
$files = hiera_hash('files',{})
create_resources ( 'profile::filed', $files )
}

