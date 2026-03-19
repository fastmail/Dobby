package Dobby::Boxmate::App::Command::cicreate;
use Dobby::Boxmate::App -command;

# ABSTRACT: create a box

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-create cicreate);
}

sub abstract { 'create a box on which to run a given CI plan' }

sub usage_desc { '%c ci-create %o PLANFILE' }

sub opt_spec {
  return (
    [ 'verbose-setup',  'print all setup output verbatim instead of summarising' ],
    [ 'username=s',     "put the box in this user's namespace", { default => $ENV{USER} }, ],
    [ 'digitalocean-ssh-key-name|K=s', 'name of key, in DO API, we want installed' ],
  );
}

sub validate_args ($self, $opt, $args) {
  @$args == 1
    || $self->usage->die({ pre_text => "No CI plan file provided.\n\n" });

  $opt->username
    || $self->usage->die({ pre_text => "Neither --username nor \$USER was supplied.\n\n" });
}

sub execute ($self, $opt, $args) {
  require Path::Tiny;
  require JSON::XS;

  my $json = Path::Tiny::path($args->[0])->slurp;
  my $plan = JSON::XS->new->decode($json);

  # TODO: validate plan?

  my $label = "ci-run-" . $plan->{run_id};

  my $ssh_key_name = $opt->digitalocean_ssh_key_name;
  unless (defined $ssh_key_name) {
    my $config = $self->app->config;
    $ssh_key_name = $config->digitalocean_ssh_key_name;
  }

  my $boxman = $self->app->boxman(verbose_setup => $opt->verbose_setup);

  my $spec = Dobby::BoxManager::ProvisionRequest->new({
    version   => 'bookworm', # TODO: make pickable
    label     => $label,
    username  => $opt->username,

    size_preferences   => $plan->{size_preferences},
    region_preferences => $plan->{region_preferences},

    project_id => q{d733cd68-8069-4815-ad49-e557a870ac0a},
    extra_tags => [ 'fminabox' ],

    run_standard_setup  => 0,
    run_custom_setup    => 0,

    digitalocean_ssh_key_name => $ssh_key_name,
  });

  my $time = time;
  say "\e[0Ksection_start:$time:creating-droplet[collapsed=true]\r\e[0KCreating Droplet";
  my $droplet = $boxman->create_droplet($spec)->get;

  my $ip = $boxman->_ip_address_for_droplet($droplet);
  my $success = $boxman->_wait_for_ssh_up($ip)->get;

  $time = time;
  say "\e[0Ksection_end:$time:creating-droplet\r\e[0K";

  $success || die "ssh never became available on box\n";
}

1;
