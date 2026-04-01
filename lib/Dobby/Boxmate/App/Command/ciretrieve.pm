package Dobby::Boxmate::App::Command::ciretrieve;
use Dobby::Boxmate::App -command;

# ABSTRACT: retrieve test artifacts from a CI box

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-retrieve-artifacts ci-retrieve ciretrieve);
}

sub abstract { 'retrieve test artifacts from a CI box' }

sub usage_desc {
  '%c ci-retrieve-artifacts %o [PLANFILE]',
}

sub opt_spec {
  return (
    [ 'username=s', "retrieve from a box in this user's namespace", { default => $ENV{USER} }, ],
    [ 'target=s',   "where to write the retrieved files", { default => "." } ],
  );
}

sub validate_args ($self, $opt, $args) {
  @$args <= 1 || $self->usage->die;

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  -r $plan_file || die "Can't read plan file $plan_file!\n";

  $opt->username
    || $self->usage->die({ pre_text => "Neither --username nor \$USER was supplied.\n\n" });
}

sub execute ($self, $opt, $args) {
  require Process::Status;

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  my $plan = $self->app->_read_plan_file($plan_file);

  my $boxman   = $self->boxman;
  my $droplet  = $boxman->_get_droplet_for($opt->username, "ci-run-$plan->{run_id}")->get;

  $droplet
    || die "Can't find the droplet to use! Did you run 'box ci-create'?\n";

  my $ip = $boxman->_ip_address_for_droplet($droplet);

  my @cmd = (
    qw(
      scp
        -o UserKnownHostsFile=/dev/null
        -o StrictHostKeyChecking=no
        -o ControlMaster=no
        -r
    ),
    "root\@$ip:/tmp/run-" . $plan->{run_id},
    $opt->target . "/run-$plan->{run_id}",
  );

  system @cmd;
  Process::Status->assert_ok("retrieving artifacts to localhost");
}

1;
