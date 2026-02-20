package Dobby::Boxmate::App::Command::scp;
use Dobby::Boxmate::App -command;

# ABSTRACT: copy files to/from a box

use v5.36.0;
use utf8;

sub abstract { 'copy files to/from a box' }

sub usage_desc {
  '%c scp %o SRC [...] DST',
}

sub opt_spec {
  return (
    [ 'username=s',           'scp to a box for this user' ],
    [ 'ssh-user=s',           'connect as this ssh user', { default => 'root' } ],
    [ 'recursive|r',          'recursively copy directories' ],
  );
}

sub validate_args ($self, $opt, $args) {
  @$args >= 2 || $self->usage->die;
}

sub execute ($self, $opt, $args) {
  my $config   = $self->app->config;
  my $boxman   = $self->boxman;
  my $username = $opt->username // $config->username;
  my $ssh_user = $opt->ssh_user;

  my @scp_args = map {; _resolve_box_arg($_, $username, $ssh_user, $boxman) } @$args;

  my @cmd = (
    qw(
      scp
        -o UserKnownHostsFile=/dev/null
        -o StrictHostKeyChecking=no
    ),
    ($opt->recursive ? '-r' : ()),
    @scp_args,
  );

  exec @cmd;

  die "Couldn't exec scp: $!\n";
}

sub _resolve_box_arg ($arg, $username, $ssh_user, $boxman) {
  my ($label, $path) = $arg =~ /\A([-_a-z0-9]+):(.*)\z/s
    or return $arg;

  my $droplet = $boxman->_get_droplet_for($username, $label)->get;

  unless ($droplet) {
    die "No droplet for $label.$username exists.\n";
  }

  my $ip = $boxman->_ip_address_for_droplet($droplet);

  return "$ssh_user\@$ip:$path";
}

1;
